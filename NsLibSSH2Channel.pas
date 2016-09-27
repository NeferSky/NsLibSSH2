unit NsLibSSH2Channel;

interface

uses
  Windows, SysUtils, Classes, WinSock, SyncObjs, libssh2, NsLibSSH2Session,
  NsLibSSH2Const;

type
  TExchangerThd = class(TThread)
  private
    FPoolIndex: Integer;
    FExchangeSocket: TSocket;
    FChannel: PLIBSSH2_CHANNEL;
  public
    property PoolIndex: Integer read FPoolIndex write FPoolIndex;
    property ExchangeSocket: TSocket read FExchangeSocket write FExchangeSocket;
    property Channel: PLIBSSH2_CHANNEL read FChannel write FChannel;
    procedure Execute; override;
    destructor Destroy; override;
  end;

type
  TExchangerRec = record
    Index: Integer;
    FExchangerThd: TExchangerThd;
  end;

type
  TExchangerPool = class(TObject)
  private
    FCount: Integer;
    FPool: array[0..MAX_POOL_SIZE - 1] of TExchangerThd;
    FSemaphore: THandle;
    procedure Clear;
    function GetFreePoolItem: Integer;
    function GetPoolItem(Index: Integer): TExchangerThd;
    procedure SetPoolItem(Index: Integer; Value: TExchangerThd);
    procedure RemovePoolThread(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    function Add(const ExchangerThd: TExchangerThd): Integer;
    procedure Remove(const Index: Integer);
    property PoolItem[Index: Integer]: TExchangerThd read GetPoolItem write SetPoolItem; default;
  end;

type
  TListenerThd = class(TThread)
  private
    FListenSocket: TSocket;
    FSockAddr: sockaddr_in;
    FSockAddrLen: Integer;
    FExchangerPool: TExchangerPool;
    FExchangeChannel: PLIBSSH2_CHANNEL;
    FExchangeSocket: TSocket;
    FSession: PLIBSSH2_SESSION;
    FRemoteHost: PAnsiChar;
    FRemotePort: Integer;

    procedure StartExchangerThread;
    procedure StopExchangerThreads;
  public
    constructor Create(CreateSuspended: Boolean);
    destructor Destroy; override;
    procedure Execute; override;
    property ListenSocket: TSocket read FListenSocket write FListenSocket;
    property SockAddr: sockaddr_in read FSockAddr write FSockAddr;
    property SockAddrLen: Integer read FSockAddrLen write FSockAddrLen;
    property Session: PLIBSSH2_SESSION read FSession write FSession;
    property RemoteHost: PAnsiChar read FRemoteHost write FRemoteHost;
    property RemotePort: Integer read FRemotePort write FRemotePort;
  end;

type
  TNsLibSSH2Channel = class(TComponent)
  private
    FSession: TNsLibSSH2Session;
    FListenerThd: TListenerThd;
    FListenSocket: TSocket;
    FLocalHost: string;
    FLocalPort: Integer;
    FRemoteHost: string;
    FRemotePort: Integer;
    FChannel: PLIBSSH2_CHANNEL;
    FOpened: Boolean;
    FStatus: string;

    SockAddr: sockaddr_in;
    SockAddrLen: Integer;

    //Events
    FAfterCreate: TNotifyEvent;
    FBeforeDestroy: TNotifyEvent;
    FBeforeOpen: TNotifyEvent;
    FAfterOpen: TNotifyEvent;
    FBeforeClose: TNotifyEvent;
    FAfterClose: TNotifyEvent;
  protected
    procedure InitProperties;
    procedure SetListenerProperties;
    function CreateListenSocket: Boolean;
    procedure CloseListenSocket;
    function CreateListenerThread: Boolean;
    procedure DestroyListenerThread;
    function StartListenerThread: Boolean;
    procedure StopListenerThread;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Open: Boolean;
    function OpenEx(ALocalHost, ARemoteHost: string;
      ALocalPort, ARemotePort: Integer): Boolean;
    procedure Close;
  published
    property AfterCreate: TNotifyEvent read FAfterCreate write FAfterCreate;
    property BeforeDestroy: TNotifyEvent read FBeforeDestroy write FBeforeDestroy;
    property BeforeOpen: TNotifyEvent read FBeforeOpen write FBeforeOpen;
    property AfterOpen: TNotifyEvent read FAfterOpen write FAfterOpen;
    property BeforeClose: TNotifyEvent read FBeforeClose write FBeforeClose;
    property AfterClose: TNotifyEvent read FAfterClose write FAfterClose;
    property Session: TNsLibSSH2Session read FSession write FSession;
    property LocalHost: string read FLocalHost write FLocalHost;
    property LocalPort: Integer read FLocalPort write FLocalPort;
    property RemoteHost: string read FRemoteHost write FRemoteHost;
    property RemotePort: Integer read FRemotePort write FRemotePort;
    property Opened: Boolean read FOpened;
    property Status: string read FStatus;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('NeferSky', [TNsLibSSH2Channel]);
end;

{ TNsLibSSH2Channel }

//---------------------------------------------------------------------------
// Public
//---------------------------------------------------------------------------

constructor TNsLibSSH2Channel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  InitProperties;

  if Assigned(AfterCreate) then AfterCreate(Self);
end;

//---------------------------------------------------------------------------

destructor TNsLibSSH2Channel.Destroy;
begin
  if Assigned(BeforeDestroy) then BeforeDestroy(Self);

  if Opened then Close;
  DestroyListenerThread;

  inherited Destroy;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Channel.Open: Boolean;
begin
  if Assigned(BeforeOpen) then BeforeOpen(Self);

  Result := False;
  
  if FSession = nil then
  begin
    FStatus := ER_SESSION_UNAVAILABLE;
    Exit;
  end;

  if Opened then Close;

  if not CreateListenSocket then Exit;

  if not CreateListenerThread then
    begin
      CloseListenSocket;
      Exit;
    end;

  SetListenerProperties;

  if not StartListenerThread then
    begin
      DestroyListenerThread;
      CloseListenSocket;
      Exit;
    end;

  FStatus := ST_CONNECTED;
  FOpened := True;
  Result := Opened;

  if Assigned(AfterOpen) then AfterOpen(Self);
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Channel.OpenEx(ALocalHost, ARemoteHost: string;
  ALocalPort, ARemotePort: Integer): Boolean;
begin
  LocalHost := ALocalHost;
  RemoteHost := ARemoteHost;
  LocalPort := ALocalPort;
  RemotePort := ARemotePort;

  Result := Open;
end;
    
//---------------------------------------------------------------------------

procedure TNsLibSSH2Channel.Close;
begin
  if Assigned(BeforeClose) then BeforeClose(Self);

  if Opened then
    begin
      StopListenerThread;
      DestroyListenerThread;
      CloseListenSocket;

      FStatus := ST_DISCONNECTED;
      FOpened := False;
    end;

  if Assigned(AfterClose) then AfterClose(Self);
end;

//---------------------------------------------------------------------------
// Protected
//---------------------------------------------------------------------------

procedure TNsLibSSH2Channel.InitProperties;
begin
  FLocalHost := DEFAULT_LOCAL_HOST;
  FLocalPort := DEFAULT_LOCAL_PORT;
  FRemoteHost := DEFAULT_REMOTE_HOST;
  FRemotePort := DEFAULT_REMOTE_PORT;
  FSession := nil;
  FChannel := nil;
  FListenerThd := nil;
  FOpened := False;
  FStatus := ST_DISCONNECTED;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Channel.SetListenerProperties;
begin
  FListenerThd.ListenSocket := FListenSocket;
  FListenerThd.SockAddr := SockAddr;
  FListenerThd.SockAddrLen := SockAddrLen;
  FListenerThd.Session := FSession.Session;
  FListenerThd.RemoteHost := PAnsiChar(FRemoteHost);
  FListenerThd.RemotePort := RemotePort;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Channel.CreateListenSocket: Boolean;
var
  SockOpt: PAnsiChar;
  rc: Integer;

begin
  Result := False;

  FListenSocket := Socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (FListenSocket = INVALID_SOCKET) then
  begin
    FListenSocket := INVALID_SOCKET;
    FStatus := ER_OPEN_SOCKET;
    Exit;
  end;

  SockAddr.sin_family := AF_INET;
  SockAddr.sin_port := htons(FLocalPort);
  SockAddr.sin_addr.s_addr := inet_addr(PAnsiChar(FLocalHost));
  if (SockAddr.sin_addr.s_addr = INADDR_NONE) then
  begin
    CloseSocket(FListenSocket);
    FListenSocket := INVALID_SOCKET;
    FStatus := ER_IP_INCORRECT;
    Exit;
  end;

  SockOpt := #1;
  SetSockOpt(FListenSocket, SOL_SOCKET, SO_REUSEADDR, SockOpt, SizeOf(SockOpt));
  SockAddrLen := SizeOf(SockAddr);

  rc := Bind(FListenSocket, SockAddr, SockAddrLen);
  if (rc = -1) then
  begin
    CloseSocket(FListenSocket);
    FListenSocket := INVALID_SOCKET;
    FStatus := Format(ER_BINDING, [WSAGetLastError]);
    Exit;
  end;

  rc := Listen(FListenSocket, 2);
  if (rc = -1) then
  begin
    CloseSocket(FListenSocket);
    FListenSocket := INVALID_SOCKET;
    FStatus := ER_SOCKET_LISTEN;
    Exit;
  end;

  Result := True;
end;
     
//---------------------------------------------------------------------------

procedure TNsLibSSH2Channel.CloseListenSocket;
begin
  if FListenSocket <> INVALID_SOCKET then
    begin
      CloseSocket(FListenSocket);
      FListenSocket := INVALID_SOCKET;
    end;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Channel.CreateListenerThread: Boolean;
begin
  Result := False;
  try
    FListenerThd := TListenerThd.Create(True);
    Result := True;
  except
    FListenerThd := nil;
  end;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Channel.DestroyListenerThread;
begin
  FreeAndNil(FListenerThd);
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Channel.StartListenerThread: Boolean;
begin
  Result := False;

  FListenerThd.Resume;
  WaitForSingleObject(FListenerThd.Handle, 1000);

  Result := True;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Channel.StopListenerThread;
begin
  if FListenerThd <> nil then
  begin
    CloseListenSocket;
    FListenerThd.Terminate;
    FListenerThd.WaitFor;
    FreeAndNil(FListenerThd);
  end;
end;

//---------------------------------------------------------------------------

{ TListenerThd }

constructor TListenerThd.Create(CreateSuspended: Boolean);
begin
  inherited Create(CreateSuspended);
  FExchangerPool := TExchangerPool.Create;
end;

//---------------------------------------------------------------------------

destructor TListenerThd.Destroy;
begin
  StopExchangerThreads;
  FExchangerPool.Destroy;
end;

//---------------------------------------------------------------------------

procedure TListenerThd.Execute;
var
  SHost: PAnsiChar;
  SPort: Integer;
  SafeCounter: Integer;

  function ExchangeSocketInvalid: Boolean;
  begin
    Result := FExchangeSocket = INVALID_SOCKET;
  end;

begin
  while not Terminated do
  begin
    FExchangeSocket := Accept(FListenSocket, @SockAddr, @SockAddrLen);
    if ExchangeSocketInvalid then Continue;

    SHost := inet_ntoa(SockAddr.sin_addr);
    SPort := ntohs(SockAddr.sin_port);

    // Unclear why the channel is not created by the first time,
    // that's why i have to make several attempts.
    // I use the SafeCounter to prevent an infinite loop.
    SafeCounter := 0;
    repeat
      Inc(SafeCounter);
      FExchangeChannel := libssh2_channel_direct_tcpip_ex(FSession,
        FRemoteHost, FRemotePort, SHost, SPort);
      // Just waiting. It's a kind of magic.
      Sleep(1000);
    until (FExchangeChannel <> nil) or (SafeCounter > MAX_CONNECTION_ATTEMPTS);

    // if exceeded MAX_CONNECTION_ATTEMPTS, but channel is still not created.
    if FExchangeChannel = nil then Continue;

    StartExchangerThread;
  end;
end;

//---------------------------------------------------------------------------

procedure TListenerThd.StartExchangerThread;
var
  ExchangerThd: TExchangerThd;
begin
  ExchangerThd := TExchangerThd.Create(True);
  ExchangerThd.FreeOnTerminate := True;
  ExchangerThd.ExchangeSocket := FExchangeSocket;
  ExchangerThd.Channel := FExchangeChannel;

  FExchangerPool.Add(ExchangerThd);
end;

//---------------------------------------------------------------------------

procedure TListenerThd.StopExchangerThreads;
begin
  FExchangerPool.Clear;
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
  while not Terminated do
  begin
    FD_ZERO(fds);
    FD_SET(FExchangeSocket, fds);
    tv.tv_sec := 0;
    tv.tv_usec := 100000;
    rc := Select(0, @fds, nil, nil, @tv);
    if (rc = -1) then
      Terminate;

    if ((rc <> 0) and FD_ISSET(FExchangeSocket, fds)) then
    begin
      FillChar(Buffer, 16385, 0);
      Len := Recv(FExchangeSocket, Buffer[0], SizeOf(Buffer), 0);

      if (Len <= 0) then
        Terminate;

      wr := 0;
      while (wr < Len) do
      begin
        i := libssh2_channel_write(Channel, @Buffer[wr], Len - wr);
        if (LIBSSH2_ERROR_EAGAIN = i) then
          Continue;

        if (i < 0) then
          Terminate;

        wr := wr + i;
      end;
    end;

    while True do
    begin
      FillChar(Buffer, 16385, 0);
      Len := libssh2_channel_read(Channel, @Buffer[0], SizeOf(Buffer));

      if (LIBSSH2_ERROR_EAGAIN = Len) then
        Break
      else if (Len < 0) then
        Terminate;

      wr := 0;
      while (wr < Len) do
      begin
        i := Send(FExchangeSocket, Buffer[wr], Len - wr, 0);
        if (i <= 0) then
          Terminate;
        wr := wr + i;
      end;
      if (libssh2_channel_eof(Channel) = 1) then
        Terminate;
    end;
  end;
end;

//---------------------------------------------------------------------------

destructor TExchangerThd.Destroy;
begin
  if (Channel <> nil) then
  begin
    libssh2_channel_close(Channel);
    libssh2_channel_wait_closed(Channel);
    libssh2_channel_free(Channel);
  end;

  if FExchangeSocket <> INVALID_SOCKET then
    begin
      CloseSocket(FExchangeSocket);
      FExchangeSocket := INVALID_SOCKET;
    end;
end;

//---------------------------------------------------------------------------

{ TExchangerPool }

constructor TExchangerPool.Create;
var
  I: Integer;
begin
  inherited Create;

  FCount := 0;

  for I := 0 to MAX_POOL_SIZE - 1 do
    PoolItem[I] := nil;
end;

//---------------------------------------------------------------------------

destructor TExchangerPool.Destroy;
begin
  Clear;

  inherited Destroy;
end;

//---------------------------------------------------------------------------

procedure TExchangerPool.Clear;
var
  I: Integer;
begin
  for I := 0 to MAX_POOL_SIZE - 1 do
  begin
    if PoolItem[I] <> nil then
    begin
      PoolItem[I].Terminate;
      PoolItem[I].WaitFor;
      PoolItem[I].Free;
      PoolItem[I] := nil;
    end;
  end;
  FCount := 0;
end;

//---------------------------------------------------------------------------

function TExchangerPool.Add(const ExchangerThd: TExchangerThd): Integer;
var
  NewPoolItemIndex: Integer;
begin
  NewPoolItemIndex := GetFreePoolItem;
  if NewPoolItemIndex = INVALID_POOL_ITEM_INDEX then
    begin
      Result := INVALID_POOL_ITEM_INDEX;
      Exit;
    end;
  PoolItem[NewPoolItemIndex] := ExchangerThd;
  PoolItem[NewPoolItemIndex].OnTerminate := RemovePoolThread;
  PoolItem[NewPoolItemIndex].PoolIndex := NewPoolItemIndex;
  PoolItem[NewPoolItemIndex].Resume;
  Inc(FCount);
  Result := 0;
end;

//---------------------------------------------------------------------------

procedure TExchangerPool.Remove(const Index: Integer);
begin
  if PoolItem[Index] <> nil then
  begin
    if not(PoolItem[Index].Terminated) then
    begin
      PoolItem[Index].Terminate;
      PoolItem[Index].WaitFor;
    end;
    PoolItem[Index].Free;
    PoolItem[Index] := nil;
    Dec(FCount);
  end;
end;

//---------------------------------------------------------------------------

function TExchangerPool.GetPoolItem(Index: Integer): TExchangerThd;
begin
  Result := FPool[Index];
end;

//---------------------------------------------------------------------------

procedure TExchangerPool.SetPoolItem(Index: Integer; Value: TExchangerThd);
begin
  FPool[Index] := Value;
end;

//---------------------------------------------------------------------------

function TExchangerPool.GetFreePoolItem: Integer;
var
  I: Integer;
begin
  Result := INVALID_POOL_ITEM_INDEX;
  for I := 0 to MAX_POOL_SIZE - 1 do
  begin
    if PoolItem[I] = nil then
      begin
        Result := I;
        Break;
      end;
  end;
end;

//---------------------------------------------------------------------------

procedure TExchangerPool.RemovePoolThread(Sender: TObject);
begin
  Remove((Sender as TExchangerThd).FPoolIndex);
end;

//---------------------------------------------------------------------------

end.

