unit NsLibSSH2Channel;
   
{
  version 1.0
}

interface

uses
  Windows, SysUtils, Classes, WinSock, libssh2, NsLibSSH2Session, NsLibSSH2Const;

type
  TChanExchangeThd = class(TThread)
  private
    FSock: TSocket;
    FChannel: PLIBSSH2_CHANNEL;
  public
    property ForwardSock: TSocket read FSock write FSock;
    property Channel: PLIBSSH2_CHANNEL read FChannel write FChannel;
    procedure Execute; override;
    destructor Destroy; override;
  end;

type
  TChanListenThd = class(TThread)
  private
    FListenSock: TSocket;
    FSockAddr: sockaddr_in;
    FSockAddrLen: Integer;
    FForwardThd: TChanExchangeThd;
    FSession: PLIBSSH2_SESSION;
    FRemoteHost: PAnsiChar;
    FRemotePort: Integer;

    SHost: PAnsiChar;
    SPort: Integer;
  public
    property ListenSock: TSocket read FListenSock write FListenSock;
    property SockAddr: sockaddr_in read FSockAddr write FSockAddr;
    property SockAddrLen: Integer read FSockAddrLen write FSockAddrLen;
    property Session: PLIBSSH2_SESSION read FSession write FSession;
    property RemoteHost: PAnsiChar read FRemoteHost write FRemoteHost;
    property RemotePort: Integer read FRemotePort write FRemotePort;
    procedure Execute; override;
    destructor Destroy; override;
    procedure FreeThreadDesc(Sender: TObject);
  end;
   
type
  TNsLibSSH2Channel = class(TComponent)
  private
    FSession: TNsLibSSH2Session;
    FListenThd: TChanListenThd;
    FLocalIP: String;
    FLocalPort: Integer;
    FRemoteHost: String;
    FRemotePort: Integer;
    FChannel: PLIBSSH2_CHANNEL;
    FOpened: Boolean;
    FStatus: String;

    SockAddr: sockaddr_in;
    SockOpt: PAnsiChar;
    SockAddrLen: Integer;
  protected
    function CreateListenSocket: Boolean;
    procedure AcceptIncomingConn;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Open: Boolean;
    procedure Close;
    procedure FreeThreadDesc(Sender: TObject);
  published
    property Session: TNsLibSSH2Session read FSession write FSession;
    property LocalIP: String read FLocalIP write FLocalIP;
    property LocalPort: Integer read FLocalPort write FLocalPort;
    property RemoteHost: String read FRemoteHost write FRemoteHost;
    property RemotePort: Integer read FRemotePort write FRemotePort;
    property Opened: Boolean read FOpened;
    property Status: String read FStatus;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('NeferSky', [TNsLibSSH2Channel]);
end;

//---------------------------------------------------------------------------

{ TNsLibSSH2Channel }

constructor TNsLibSSH2Channel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FLocalIP := '127.0.0.1';
  FLocalPort := 3389;
  FRemoteHost := '192.168.1.1';
  FRemotePort := 3389;
  FSession := nil;
  FChannel := nil;
  FOpened := False;
  FStatus := 'Disconnected';
end;

//---------------------------------------------------------------------------

destructor TNsLibSSH2Channel.Destroy;
begin
  if Opened then Close;
  FListenThd.Free;

  inherited Destroy;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Channel.Open: Boolean;
begin
  Result := False;
  if Opened then Close;

  if FSession = nil then
    raise Exception.Create('Session is not available');

  if not CreateListenSocket then
    raise Exception.Create(FStatus);
  AcceptIncomingConn;

  FStatus := 'Connected';
  FOpened := True;
  Result := Opened;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Channel.CreateListenSocket: Boolean;
var
  L: TSocket;
begin
  Result := False;

  if FListenThd <> nil then Exit;

  L := Socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (L = INVALID_SOCKET) then
    begin
      FStatus := 'Failed to open listen socket';
      Exit;
    end;

  FListenThd := TChanListenThd.Create(True);
  FListenThd.FreeOnTerminate := True;
  FListenThd.OnTerminate := FreeThreadDesc;
  FListenThd.ListenSock := L;
  SockAddr.sin_family := AF_INET;
  SockAddr.sin_port := htons(FLocalPort);
  SockAddr.sin_addr.S_addr := inet_addr(PAnsiChar(FLocalIP));
  if ((INADDR_NONE = SockAddr.sin_addr.s_addr) and (INADDR_NONE = inet_addr(PAnsiChar(FLocalIP)))) then
    begin
      FStatus := 'IP address is wrong';
      Exit;
    end;

  SockOpt := #1;
  SetSockOpt(FListenThd.ListenSock, SOL_SOCKET, SO_REUSEADDR, SockOpt, SizeOf(SockOpt));
  SockAddrLen := SizeOf(SockAddr);

  if (Bind(FListenThd.ListenSock, SockAddr, SockAddrLen) = -1) then
    begin
      FStatus := 'Cannot bind socket with IP address' + IntToStr(WSAGetLastError);
      Exit;
    end;

  if (Listen(FListenThd.ListenSock, 2) = -1) then
    begin
      FStatus := 'Socket cannot listen';
      Exit;
    end;

  Result := True;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Channel.AcceptIncomingConn;
begin
  FListenThd.SockAddr := SockAddr;
  FListenThd.SockAddrLen := SockAddrLen;
  FListenThd.Session := FSession.Session;
  FListenThd.RemoteHost := PAnsiChar(FRemoteHost);
  FListenThd.RemotePort := RemotePort;
  FListenThd.Resume;
  WaitForSingleObject(FListenThd.Handle, 1000);
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Channel.Close;
begin
  if FListenThd.ListenSock <> INVALID_SOCKET then
    begin
      CloseSocket(FListenThd.ListenSock);
      FListenThd.Terminate;
      FListenThd.WaitFor;
      FListenThd.Free;
    end;

  FStatus := 'Disconnected';
  FOpened := False;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Channel.FreeThreadDesc(Sender: TObject);
begin
  FListenThd := nil;
end;
  
//---------------------------------------------------------------------------

{ TChanListenThd }

procedure TChanListenThd.Execute;
var
  F: TSocket;
begin
  while not Terminated do
    begin
      F := Accept(FListenSock, @SockAddr, @SockAddrLen);

      if (F = INVALID_SOCKET) then Exit;

      if FForwardThd <> nil then Continue;

      FForwardThd := TChanExchangeThd.Create(True);
      FForwardThd.OnTerminate := FreeThreadDesc;

      SHost := inet_ntoa(SockAddr.sin_addr);
      SPort := ntohs(SockAddr.sin_port);

      FForwardThd.ForwardSock := F;
      FForwardThd.Channel := libssh2_channel_direct_tcpip_ex(FSession, FRemoteHost,
        FRemotePort, SHost, SPort);

      // A code block below is a kind of magic
      if (FForwardThd.Channel = nil) then
        begin
          Sleep(100);
          FForwardThd.Channel := libssh2_channel_direct_tcpip_ex(FSession, FRemoteHost,
            FRemotePort, SHost, SPort);
          if (FForwardThd.Channel = nil) then
            begin
              FForwardThd.Free;
              FForwardThd := nil;
              Continue;
            end;
        end;

      libssh2_session_set_blocking(FSession, 0);

      FForwardThd.FreeOnTerminate := True;
      FForwardThd.Resume;
      WaitForSingleObject(FForwardThd.Handle, 1000);
    end;
end;

//---------------------------------------------------------------------------

destructor TChanListenThd.Destroy;
begin

  if FListenSock <> INVALID_SOCKET then
    CloseSocket(FListenSock);

  if FForwardThd <> nil then
    begin
      FForwardThd.Terminate;
      FForwardThd.WaitFor;
      FForwardThd.Free;
    end;
end;

//---------------------------------------------------------------------------

procedure TChanListenThd.FreeThreadDesc(Sender: TObject);
begin
  FForwardThd := nil;
end;
 
//---------------------------------------------------------------------------

{ TChanExchangeThd }

procedure TChanExchangeThd.Execute;
var
  i: Integer;
  wr: ssize_t;
  rc: Integer;
  tv: timeval;
  fds: tfdset;
  Len: ssize_t;
  Buf: array[0..16384] of Char;

begin
  while not Terminated do
    begin
      FD_ZERO(fds);
      FD_SET(ForwardSock, fds);
      tv.tv_sec := 0;
      tv.tv_usec := 100000;
      rc := Select(0, @fds, nil, nil, @tv);
      if (rc = -1) then Terminate;

      if ((rc <> 0) and FD_ISSET(ForwardSock, fds)) then
        begin
          FillChar(Buf, 16385, 0);
          Len := Recv(ForwardSock, Buf[0], SizeOf(Buf), 0);

          if (Len <= 0) then Terminate;

          wr := 0;
          while (wr < Len) do
            begin
              i := libssh2_channel_write(Channel, @Buf[wr], Len - wr);
              if (LIBSSH2_ERROR_EAGAIN = i) then Continue;

              if (i < 0) then Terminate;

              wr := wr + i;
            end;
        end;

      while True do
        begin
          FillChar(Buf, 16385, 0);
          Len := libssh2_channel_read(Channel, @Buf[0], SizeOf(Buf));

          if (LIBSSH2_ERROR_EAGAIN = Len) then
            Break
          else
            if (Len < 0) then Terminate;

          wr := 0;
          while (wr < Len) do
            begin
              i := Send(ForwardSock, Buf[wr], Len - wr, 0);
              if (i <= 0) then Terminate;
              wr := wr + i;
            end;
          if (libssh2_channel_eof(Channel) = 1) then Terminate;
        end;
    end;
end;

//---------------------------------------------------------------------------

destructor TChanExchangeThd.Destroy;
begin
  CloseSocket(ForwardSock);
  ForwardSock := INVALID_SOCKET;

  if (Channel <> nil) then
    begin
      libssh2_channel_close(Channel);
      libssh2_channel_wait_closed(Channel);
      libssh2_channel_free(Channel);
    end;
end;

end.
