unit NsLibSSH2Channel;

//{$define DEBUG_CHANNEL}
//{$define DEBUG_LISTENER}
//{$define DEBUG_EXCHANGER}

interface

uses
  Windows, SysUtils, Classes, WinSock, libssh2, NsLibSSH2Session, NsLibSSH2Const;

type
  TExchangerThd = class(TThread)
  private
    FSocket: TSocket;
    FChannel: PLIBSSH2_CHANNEL;
  public
    property Socket: TSocket read FSocket write FSocket;
    property Channel: PLIBSSH2_CHANNEL read FChannel write FChannel;
    procedure Execute; override;
    destructor Destroy; override;
  end;

type
  TListenerThd = class(TThread)
  private
    FSocket: TSocket;
    FSockAddr: sockaddr_in;
    FSockAddrLen: Integer;
    FExchangerThd: TExchangerThd;
    FSession: PLIBSSH2_SESSION;
    FRemoteHost: PAnsiChar;
    FRemotePort: Integer;

    SHost: PAnsiChar;
    SPort: Integer;
  public
    property Socket: TSocket read FSocket write FSocket;
    property SockAddr: sockaddr_in read FSockAddr write FSockAddr;
    property SockAddrLen: Integer read FSockAddrLen write FSockAddrLen;
    property Session: PLIBSSH2_SESSION read FSession write FSession;
    property RemoteHost: PAnsiChar read FRemoteHost write FRemoteHost;
    property RemotePort: Integer read FRemotePort write FRemotePort;
    procedure Execute; override;
    destructor Destroy; override;
    procedure FreeExchangerThreadDesc(Sender: TObject);
  end;
   
type
  TNsLibSSH2Channel = class(TComponent)
  private
    FSession: TNsLibSSH2Session;
    FListenerThd: TListenerThd;
    FLocalHost: String;
    FLocalPort: Integer;
    FRemoteHost: String;
    FRemotePort: Integer;
    FChannel: PLIBSSH2_CHANNEL;
    FOpened: Boolean;
    FStatus: String;

    SockAddr: sockaddr_in;
    SockOpt: PAnsiChar;
    SockAddrLen: Integer;

    //Events
    FAfterCreate: TNotifyEvent;
    FBeforeDestroy: TNotifyEvent;
    FBeforeOpen: TNotifyEvent;
    FAfterOpen: TNotifyEvent;
    FBeforeClose: TNotifyEvent;
    FAfterClose: TNotifyEvent;
  protected
    function CreateListenSocket: Boolean;
    procedure AcceptIncomingConnections;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Open: Boolean;
    function OpenEx(ALocalHost, ARemoteHost: String;
      ALocalPort, ARemotePort: Integer): Boolean;
    procedure Close;
    procedure CloseEx;
    procedure FreeListenerThreadDesc(Sender: TObject);
  published
    property AfterCreate: TNotifyEvent read FAfterCreate write FAfterCreate;
    property BeforeDestroy: TNotifyEvent read FBeforeDestroy write FBeforeDestroy;
    property BeforeOpen: TNotifyEvent read FBeforeOpen write FBeforeOpen;
    property AfterOpen: TNotifyEvent read FAfterOpen write FAfterOpen;
    property BeforeClose: TNotifyEvent read FBeforeClose write FBeforeClose;
    property AfterClose: TNotifyEvent read FAfterClose write FAfterClose;
    property Session: TNsLibSSH2Session read FSession write FSession;
    property LocalHost: String read FLocalHost write FLocalHost;
    property LocalPort: Integer read FLocalPort write FLocalPort;
    property RemoteHost: String read FRemoteHost write FRemoteHost;
    property RemotePort: Integer read FRemotePort write FRemotePort;
    property Opened: Boolean read FOpened;
    property Status: String read FStatus;
  end;

procedure Register;

implementation

uses
  Dialogs;

procedure Register;
begin
  RegisterComponents('NeferSky', [TNsLibSSH2Channel]);
end;

//---------------------------------------------------------------------------

{ TNsLibSSH2Channel }

constructor TNsLibSSH2Channel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  {$ifdef DEBUG_CHANNEL}
  DebugLog('* TNsLibSSH2Channel.Create');
  {$endif}

  FLocalHost := DEFAULT_LOCAL_HOST;
  FLocalPort := DEFAULT_LOCAL_PORT;
  FRemoteHost := DEFAULT_REMOTE_HOST;
  FRemotePort := DEFAULT_REMOTE_PORT;
  FSession := nil;
  FChannel := nil;
  FOpened := VAL_FALSE;
  FStatus := ST_DISCONNECTED;

  {$ifdef DEBUG_CHANNEL}
  DebugLog('~ TNsLibSSH2Channel.Create');
  {$endif}

  if Assigned(AfterCreate) then AfterCreate(Self);
end;

//---------------------------------------------------------------------------

destructor TNsLibSSH2Channel.Destroy;
begin
  if Assigned(BeforeDestroy) then BeforeDestroy(Self);

  {$ifdef DEBUG_CHANNEL}
  DebugLog('* TNsLibSSH2Channel.Destroy');
  {$endif}

  if Opened then Close;
  FListenerThd.Free;

  {$ifdef DEBUG_CHANNEL}
  DebugLog('~ TNsLibSSH2Channel.Destroy');
  {$endif}

  inherited Destroy;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Channel.Open: Boolean;
begin
  if Assigned(BeforeOpen) then BeforeOpen(Self);

  {$ifdef DEBUG_CHANNEL}
  DebugLog('* TNsLibSSH2Channel.Open');
  {$endif}

  if Opened then Close;

  if FSession = nil then
    raise Exception.Create(ER_SESSION_UNAVAILABLE);

  if not CreateListenSocket then
    raise Exception.Create(FStatus);
  AcceptIncomingConnections;

  FStatus := ST_CONNECTED;
  FOpened := True;
  Result := Opened;
       
  {$ifdef DEBUG_CHANNEL}
  DebugLog('~ TNsLibSSH2Channel.Open');
  {$endif}

  if Assigned(AfterOpen) then AfterOpen(Self);
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Channel.OpenEx(ALocalHost, ARemoteHost: String;
  ALocalPort, ARemotePort: Integer): Boolean;
begin
  {$ifdef DEBUG_CHANNEL}
  DebugLog('* TNsLibSSH2Channel.OpenEx');
  {$endif}

  Result := False;

  LocalHost := ALocalHost;
  RemoteHost := ARemoteHost;
  LocalPort := ALocalPort;
  RemotePort := ARemotePort;

  try
    Open;
  except
    {$ifdef DEBUG_CHANNEL}
    DebugLog('TNsLibSSH2Channel.OpenEx : Open-Except');
    DebugLog('~ TNsLibSSH2Channel.OpenEx');
    {$endif}
    Exit;
  end;

  Result := True;

  {$ifdef DEBUG_CHANNEL}
  DebugLog('~ TNsLibSSH2Channel.OpenEx');
  {$endif}

end;

//---------------------------------------------------------------------------

function TNsLibSSH2Channel.CreateListenSocket: Boolean;
var
  ListenSocket: TSocket;
begin
  {$ifdef DEBUG_CHANNEL}
  DebugLog('* TNsLibSSH2Channel.CreateListenSocket');
  {$endif}

  Result := False;

  if FListenerThd <> nil then
  begin
    {$ifdef DEBUG_CHANNEL}
    DebugLog('~ TNsLibSSH2Channel.CreateListenSocket : FListenerThd <> nil');
    {$endif}
    Exit;
  end;

  ListenSocket := Socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);
  {$ifdef DEBUG_CHANNEL}
  DebugLog('TNsLibSSH2Channel.CreateListenSocket : Create ListenSocket = ' + IntToStr(ListenSocket));
  {$endif}

  if (ListenSocket = INVALID_SOCKET) then
    begin
      FStatus := ER_OPEN_SOCKET;
      {$ifdef DEBUG_CHANNEL}
      DebugLog('~ TNsLibSSH2Channel.CreateListenSocket : ListenSocket = INVALID_SOCKET');
      {$endif}
      Exit;
    end;

  FListenerThd := TListenerThd.Create(True);
  {$ifdef DEBUG_CHANNEL}
  DebugLog('TNsLibSSH2Channel.CreateListenSocket : Create FListenerThd.Handle = ' + IntToStr(FListenerThd.Handle));
  {$endif}
  FListenerThd.FreeOnTerminate := True;
  FListenerThd.OnTerminate := FreeListenerThreadDesc;
  FListenerThd.Socket := ListenSocket;
  {$ifdef DEBUG_CHANNEL}
  DebugLog('TNsLibSSH2Channel.CreateListenSocket : Set FListenerThd.Socket = ' + IntToStr(FListenerThd.Socket));
  {$endif}
  SockAddr.sin_family := AF_INET;
  SockAddr.sin_port := htons(FLocalPort);
  SockAddr.sin_addr.S_addr := inet_addr(PAnsiChar(FLocalHost));
  if ((INADDR_NONE = SockAddr.sin_addr.s_addr) and (INADDR_NONE = inet_addr(PAnsiChar(FLocalHost)))) then
    begin
      FStatus := ER_IP_INCORRECT;
      {$ifdef DEBUG_CHANNEL}
      DebugLog('~ TNsLibSSH2Channel.CreateListenSocket : IP Incorrect');
      {$endif}
      Exit;
    end;

  SockOpt := #1;
  SetSockOpt(FListenerThd.Socket, SOL_SOCKET, SO_REUSEADDR, SockOpt, SizeOf(SockOpt));
  SockAddrLen := SizeOf(SockAddr);

  if (Bind(FListenerThd.Socket, SockAddr, SockAddrLen) = -1) then
    begin
      FStatus := Format(ER_BINDING, [WSAGetLastError]);
      {$ifdef DEBUG_CHANNEL}
      DebugLog('~ TNsLibSSH2Channel.CreateListenSocket : Bind = -1');
      {$endif}
      Exit;
    end;

  if (Listen(FListenerThd.Socket, 2) = -1) then
    begin
      FStatus := ER_SOCKET_LISTEN;
      {$ifdef DEBUG_CHANNEL}
      DebugLog('~ TNsLibSSH2Channel.CreateListenSocket : ListenSocket = -1');
      {$endif}
      Exit;
    end;

  Result := True;

  {$ifdef DEBUG_CHANNEL}
  DebugLog('~ TNsLibSSH2Channel.CreateListenSocket');
  {$endif}
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Channel.AcceptIncomingConnections;
begin
  {$ifdef DEBUG_CHANNEL}
  DebugLog('* TNsLibSSH2Channel.AcceptIncomingConnections');
  {$endif}
  FListenerThd.SockAddr := SockAddr;
  FListenerThd.SockAddrLen := SockAddrLen;
  FListenerThd.Session := FSession.Session;
  FListenerThd.RemoteHost := PAnsiChar(FRemoteHost);
  FListenerThd.RemotePort := RemotePort;
  {$ifdef DEBUG_CHANNEL}
  DebugLog('TNsLibSSH2Channel.AcceptIncomingConnections : Resume FListenerThd.Handle = ' + IntToStr(FListenerThd.Handle));
  {$endif}
  FListenerThd.Resume;
  WaitForSingleObject(FListenerThd.Handle, 1000);
  {$ifdef DEBUG_CHANNEL}
  DebugLog('~ TNsLibSSH2Channel.AcceptIncomingConnections');
  {$endif}
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Channel.Close;
begin
  if Assigned(BeforeClose) then BeforeClose(Self);

  {$ifdef DEBUG_CHANNEL}
  DebugLog('* TNsLibSSH2Channel.Close');
  {$endif}

  if FListenerThd.Socket <> INVALID_SOCKET then
    begin
      {$ifdef DEBUG_CHANNEL}
      DebugLog('TNsLibSSH2Channel.Close : Close socket = ' + IntToStr(FListenerThd.Socket));
      {$endif}
      CloseSocket(FListenerThd.Socket);
      {$ifdef DEBUG_CHANNEL}
      DebugLog('TNsLibSSH2Channel.Close : Terminate FListenerThd.Handle = ' + IntToStr(FListenerThd.Handle));
      {$endif}
      FListenerThd.Terminate;
      {$ifdef DEBUG_CHANNEL}
      DebugLog('TNsLibSSH2Channel.Close : WaitFor FListenerThd.Handle = ' + IntToStr(FListenerThd.Handle));
      {$endif}
      FListenerThd.WaitFor;
      {$ifdef DEBUG_CHANNEL}
      DebugLog('TNsLibSSH2Channel.Close : Free FListenerThd.Handle = ' + IntToStr(FListenerThd.Handle));
      {$endif}
      FListenerThd.Free;
      {$ifdef DEBUG_CHANNEL}
      DebugLog('TNsLibSSH2Channel.Close : Set nil FListenerThd.Handle = ' + IntToStr(FListenerThd.Handle));
      {$endif}
      FListenerThd := nil;
    end;

  FStatus := ST_DISCONNECTED;
  FOpened := False;

  {$ifdef DEBUG_CHANNEL}
  DebugLog('~ TNsLibSSH2Channel.Close');
  {$endif}

  if Assigned(AfterClose) then AfterClose(Self);
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Channel.CloseEx;
begin
  {$ifdef DEBUG_CHANNEL}
  DebugLog('* TNsLibSSH2Channel.CloseEx');
  {$endif}
  if Opened then Close;
  {$ifdef DEBUG_CHANNEL}
  DebugLog('~ TNsLibSSH2Channel.CloseEx');
  {$endif}
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Channel.FreeListenerThreadDesc(Sender: TObject);
begin
  {$ifdef DEBUG_LISTENER}
//  DebugLog('* TNsLibSSH2Channel.FreeListenerThreadDesc');
  {$endif}
  {$ifdef DEBUG_LISTENER}
//  DebugLog('TNsLibSSH2Channel.FreeListenerThreadDesc : Set nil FListenerThd = ' + IntToStr(FListenerThd.Handle));
  {$endif}
  FListenerThd := nil;
  {$ifdef DEBUG_LISTENER}
//  DebugLog('~ TNsLibSSH2Channel.FreeListenerThreadDesc');
  {$endif}
end;

//---------------------------------------------------------------------------

{ TListenerThd }

procedure TListenerThd.Execute;
var
  ExchangeSocket: TSocket;
begin
  {$ifdef DEBUG_LISTENER}
  DebugLog('* TListenerThd.Execute');
  {$endif}

  while not Terminated do
    begin
      ExchangeSocket := Accept(FSocket, @SockAddr, @SockAddrLen);
      {$ifdef DEBUG_LISTENER}
      DebugLog('TListenerThd.Execute : Create ExchangeSocket = ' + IntToStr(ExchangeSocket));
      {$endif}

      if (ExchangeSocket = INVALID_SOCKET) then
        begin
          {$ifdef DEBUG_LISTENER}
          DebugLog('~ TListenerThd.Execute : ExchangeSocket = INVALID_SOCKET');
          {$endif}
          Exit;
        end;

      if FExchangerThd <> nil then
        begin
          {$ifdef DEBUG_LISTENER}
          DebugLog('TListenerThd.Execute : Continue, FExchangerThd <> nil');
          {$endif}
          Continue;
        end;

      SHost := inet_ntoa(SockAddr.sin_addr);
      SPort := ntohs(SockAddr.sin_port);

      FExchangerThd := TExchangerThd.Create(True);
      {$ifdef DEBUG_LISTENER}
      DebugLog('TListenerThd.Execute : Create FExchangerThd.Handle = ' + IntToStr(FExchangerThd.Handle));
      {$endif}
      FExchangerThd.OnTerminate := FreeExchangerThreadDesc;
      FExchangerThd.Socket := ExchangeSocket;
      {$ifdef DEBUG_LISTENER}
      DebugLog('TListenerThd.Execute : Set FExchangerThd.Socket = ' + IntToStr(FExchangerThd.Socket));
      {$endif}
      {$ifdef DEBUG_LISTENER}
      DebugLog('TListenerThd.Execute : Try create FExchangerThd.Channel...');
      {$endif}

      FExchangerThd.Channel := libssh2_channel_direct_tcpip_ex(FSession, FRemoteHost,
        FRemotePort, SHost, SPort);

      if (FExchangerThd.Channel = nil) then
        begin
          {$ifdef DEBUG_LISTENER}
          DebugLog('TListenerThd.Execute : FExchangerThd.Channel = nil');
          {$endif}
          {$ifdef DEBUG_LISTENER}
          DebugLog('TListenerThd.Execute : Free FExchangerThd.Handle = ' + IntToStr(FExchangerThd.Handle));
          {$endif}
          FExchangerThd.Free;
          {$ifdef DEBUG_LISTENER}
          DebugLog('TListenerThd.Execute : Set nil FExchangerThd.Handle = ' + IntToStr(FExchangerThd.Handle));
          {$endif}
          FExchangerThd := nil;
          {$ifdef DEBUG_LISTENER}
          DebugLog('TListenerThd.Execute : Continue');
          {$endif}
          Continue;
        end;

      libssh2_session_set_blocking(FSession, 0);

      FExchangerThd.FreeOnTerminate := True;
      {$ifdef DEBUG_LISTENER}
      DebugLog('TListenerThd.Execute : Resume FExchangerThd.Handle = ' + IntToStr(FExchangerThd.Handle));
      {$endif}
      FExchangerThd.Resume;
      WaitForSingleObject(FExchangerThd.Handle, 1000);
    end;

  {$ifdef DEBUG_LISTENER}
  DebugLog('~ TListenerThd.Execute');
  {$endif}
end;

//---------------------------------------------------------------------------

destructor TListenerThd.Destroy;
begin
  {$ifdef DEBUG_LISTENER}
  DebugLog('* TListenerThd.Destroy');
  {$endif}

  if FSocket <> INVALID_SOCKET then
    begin
      {$ifdef DEBUG_LISTENER}
      DebugLog('TListenerThd.Destroy : Close Socket = ' + IntToStr(FSocket));
      {$endif}
      CloseSocket(FSocket);
    end
  else
    begin
      {$ifdef DEBUG_LISTENER}
      DebugLog('TListenerThd.Destroy : Socket is nil');
      {$endif}
    end;

  if FExchangerThd <> nil then
    begin
      {$ifdef DEBUG_LISTENER}
      DebugLog('TListenerThd.Destroy : Terminate FExchangerThd.Handle = ' + IntToStr(FExchangerThd.Handle));
      {$endif}
      FExchangerThd.Terminate;
      {$ifdef DEBUG_LISTENER}
      DebugLog('TListenerThd.Destroy : WaitFor FExchangerThd.Handle = ' + IntToStr(FExchangerThd.Handle));
      {$endif}
      FExchangerThd.WaitFor;
      {$ifdef DEBUG_LISTENER}
      DebugLog('TListenerThd.Destroy : Free FExchangerThd.Handle = ' + IntToStr(FExchangerThd.Handle));
      {$endif}
      FExchangerThd.Free;
    end
  else
    begin
      {$ifdef DEBUG_LISTENER}
      DebugLog('TListenerThd.Destroy : Socket is nil');
      {$endif}
    end;

  {$ifdef DEBUG_LISTENER}
  DebugLog('~ TListenerThd.Destroy');
  {$endif}
end;

//---------------------------------------------------------------------------

procedure TListenerThd.FreeExchangerThreadDesc(Sender: TObject);
begin
  {$ifdef DEBUG_EXCHANGER}
  DebugLog('* TListenerThd.FreeExchangerThreadDesc');
  {$endif}
  {$ifdef DEBUG_EXCHANGER}
  DebugLog('TListenerThd.FreeExchangerThreadDesc : Set nil FExchangerThd = ' + IntToStr(FExchangerThd.Handle));
  {$endif}
  FExchangerThd := nil;
  {$ifdef DEBUG_EXCHANGER}
  DebugLog('~ TListenerThd.FreeExchangerThreadDesc');
  {$endif}
end;

//---------------------------------------------------------------------------

{ TExchangerThd }

procedure TExchangerThd.Execute;
var
  i: Integer;
  wr: ssize_t;
  rc: Integer;
  tv: timeval;
  fds: tfdset;
  Len: ssize_t;
  Buffer: array[0..16384] of Char;

begin
  {$ifdef DEBUG_EXCHANGER}
  DebugLog('* TExchangerThd.Execute');
  {$endif}
  {$ifdef DEBUG_EXCHANGER}
  DebugLog('TExchangerThd.Execute : Handle = ' + IntToStr(Handle));
  {$endif}
  while not Terminated do
    begin
      FD_ZERO(fds);
      FD_SET(Socket, fds);
      tv.tv_sec := 0;
      tv.tv_usec := 100000;
      rc := Select(0, @fds, nil, nil, @tv);
      if (rc = -1) then Terminate;

      if ((rc <> 0) and FD_ISSET(Socket, fds)) then
        begin
          FillChar(Buffer, 16385, 0);
          Len := Recv(Socket, Buffer[0], SizeOf(Buffer), 0);

          if (Len <= 0) then Terminate;

          wr := 0;
          while (wr < Len) do
            begin
              i := libssh2_channel_write(Channel, @Buffer[wr], Len - wr);
              if (LIBSSH2_ERROR_EAGAIN = i) then Continue;

              if (i < 0) then Terminate;

              wr := wr + i;
            end;
        end;

      while True do
        begin
          FillChar(Buffer, 16385, 0);
          Len := libssh2_channel_read(Channel, @Buffer[0], SizeOf(Buffer));

          if (LIBSSH2_ERROR_EAGAIN = Len) then
            Break
          else
            if (Len < 0) then Terminate;

          wr := 0;
          while (wr < Len) do
            begin
              i := Send(Socket, Buffer[wr], Len - wr, 0);
              if (i <= 0) then Terminate;
              wr := wr + i;
            end;
          if (libssh2_channel_eof(Channel) = 1) then Terminate;
        end;
    end;
  {$ifdef DEBUG_EXCHANGER}
  DebugLog('~ TExchangerThd.Execute');
  {$endif}
end;

//---------------------------------------------------------------------------

destructor TExchangerThd.Destroy;
begin
  {$ifdef DEBUG_EXCHANGER}
  DebugLog('* TExchangerThd.Destroy');
  {$endif}

  {$ifdef DEBUG_EXCHANGER}
  DebugLog('TExchangerThd.Destroy : Close socket = ' + IntToStr(Socket));
  {$endif}
  CloseSocket(Socket);
  {$ifdef DEBUG_EXCHANGER}
  DebugLog('TExchangerThd.Destroy : Set invalid socket = ' + IntToStr(Socket));
  {$endif}
  Socket := INVALID_SOCKET;

  if (Channel <> nil) then
    begin
      {$ifdef DEBUG_EXCHANGER}
      DebugLog('TExchangerThd.Destroy : Close and free LibSSH Channel (not nil)');
      {$endif}
      libssh2_channel_close(Channel);
      libssh2_channel_wait_closed(Channel);
      libssh2_channel_free(Channel);
    end
  else
    begin
      {$ifdef DEBUG_EXCHANGER}
      DebugLog('TExchangerThd.Destroy : LibSSH Channel is nil');
      {$endif}
    end;

  {$ifdef DEBUG_EXCHANGER}
  DebugLog('~ TExchangerThd.Destroy');
  {$endif}
end;

//---------------------------------------------------------------------------

end.

