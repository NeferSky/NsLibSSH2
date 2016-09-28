unit NsLibSSH2Terminal;

interface

uses
  StdCtrls, SysUtils, Classes, WinSock, libssh2, NsLibSSH2Session, NsLibSSH2Const,
  NsLibSSH2Threads;
      
type
  TExchangerThd = class(TThread)
  private
    FPoolIndex: Integer;
    FExchangeSocket: TSocket;
    FChannel: PLIBSSH2_CHANNEL;

    // Property getters/setters
    function GetPoolIndex: Integer;
    procedure SetPoolIndex(Value: Integer);
    function GetExchangeSocket: TSocket;
    procedure SetExchangeSocket(Value: TSocket);
    function GetChannel: PLIBSSH2_CHANNEL;
    procedure SetChannel(Value: PLIBSSH2_CHANNEL);
    function GetTerminated: Boolean;
  public
    destructor Destroy; override;
    procedure Execute; override;
    property PoolIndex: Integer read GetPoolIndex write SetPoolIndex;
    property ExchangeSocket: TSocket read GetExchangeSocket write
      SetExchangeSocket;
    property Channel: PLIBSSH2_CHANNEL read GetChannel write SetChannel;
    property Terminated: Boolean read GetTerminated;
  end;

type
  TNsLibSSH2Terminal = class(TComponent)
  private
    FSession: TNsLibSSH2Session;
    FChannel: PLIBSSH2_CHANNEL;
    FVariables: TStrings;
    FOpened: Boolean;
    FStatus: String;
    FTerminal: String;
    FExchangerThd: TExchangerThd;

    procedure PostVarsToServer;

    // Property getters/setters
    function GetTerminal: String;
    procedure SetTerminal(Value: String);
    function GetSession: TNsLibSSH2Session;
    procedure SetSession(Value: TNsLibSSH2Session);
    function GetVariables: TStrings;
    procedure SetVariables(Value: TStrings);
    function GetOpened: Boolean;
    function GetStatus: String;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Open: Boolean;
    procedure Close;
    property Terminal: String read GetTerminal write SetTerminal;
    property Session: TNsLibSSH2Session read GetSession write SetSession;
    property Variables: TStrings read GetVariables write SetVariables;
    property Opened: Boolean read GetOpened;
    property Status: String read GetStatus;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('NeferSky', [TNsLibSSH2Terminal]);
end;

//---------------------------------------------------------------------------

{ TNsLibSSH2Terminal }
// Public

constructor TNsLibSSH2Terminal.Create(AOwner: TComponent);
begin
  inherited;

  FSession := nil;
  FChannel := nil;
  FVariables.Clear;
  FTerminal := 'xterm';
  FSession := nil;
  FOpened := False;
  FStatus := ST_DISCONNECTED;
end;
   
//---------------------------------------------------------------------------

destructor TNsLibSSH2Terminal.Destroy;
begin
  if Opened then Close;
  FVariables.Clear;

  inherited;
end;
  
//---------------------------------------------------------------------------

function TNsLibSSH2Terminal.Open: Boolean;
var
  rc: Integer;
begin
  Result := False;

  if FSession = nil then
    raise Exception.Create(ER_SESSION_UNAVAILABLE);

{  // Unclear why the channel is not created by the first time,
  // that's why i have to make several attempts.
  // I use the SafeCounter to prevent an infinite loop.
  SafeCounter := 0;
  repeat
    Inc(SafeCounter);
    }
    FChannel := libssh2_channel_open_session(FSession.Session);
{    // Just waiting. It's a kind of magic.
    Sleep(1000);
  until (FExchangeChannel <> nil) or (SafeCounter > MAX_CONNECTION_ATTEMPTS);
  }

  if (FChannel = nil) then
  begin
    FStatus := ER_CHANNEL_OPEN;
    Exit;
  end;

  PostVarsToServer;

  rc := libssh2_channel_request_pty(FChannel, PAnsiChar(FTerminal));
  if (rc <> 0) then
    begin
      FStatus := ER_FAILED_PTY;
      Close;
    end;

  rc := libssh2_channel_shell(FChannel);
  if (rc <> 0) then
    begin
      FStatus := ER_REQUEST_SHELL;
      Exit;
    end;





{  FListenSocket := Socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (FListenSocket = INVALID_SOCKET) then
  begin
    FListenSocket := INVALID_SOCKET;
    FStatus := ER_OPEN_SOCKET;
    Exit;
  end;

  ExchangerThd := TExchangerThd.Create(True);
  ExchangerThd.FreeOnTerminate := True;
  ExchangerThd.ExchangeSocket := FExchangeSocket;
  ExchangerThd.Channel := FExchangeChannel;

 }



{    /* At this point the shell can be interacted with using
     * libssh2_channel_read()
     * libssh2_channel_read_stderr()
     * libssh2_channel_write()
     * libssh2_channel_write_stderr()
     *
     * Blocking mode may be (en|dis)abled with: libssh2_channel_set_blocking()
     * If the server send EOF, libssh2_channel_eof() will return non-0
     * To send EOF to the server use: libssh2_channel_send_eof()
     * A channel can be closed with: libssh2_channel_close()
     * A channel can be freed with: libssh2_channel_free()
     */
 }


  FStatus := ST_CONNECTED;
  FOpened := True;
  Result := Opened;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Terminal.Close;
begin
  if FChannel <> nil then
    begin
      libssh2_channel_close(FChannel);
      libssh2_channel_free(FChannel);
      FChannel := nil;
    end;

  FStatus := ST_DISCONNECTED;
  FOpened := False;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Terminal.PostVarsToServer;
var
  i, rc: Integer;
  Variable: String;
  VarKey, VarVal: PAnsiChar;
begin
  if FVariables.Count <= 0 then Exit;
  for i := 0 to FVariables.Count - 1 do
    begin
      Variable := FVariables[i];
      VarKey := PAnsiChar(Variable);
      VarVal := PAnsiChar(Variable);
      rc := libssh2_channel_setenv(FChannel, VarKey, VarVal);
      if rc <> 0 then Continue;
    end;
end;
  
//---------------------------------------------------------------------------
// Public

function TNsLibSSH2Terminal.GetOpened: Boolean;
begin
  Result := FOpened;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Terminal.GetSession: TNsLibSSH2Session;
begin
  Result := FSession;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Terminal.GetStatus: String;
begin
  Result := FStatus;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Terminal.GetTerminal: String;
begin
  Result := FTerminal;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Terminal.GetVariables: TStrings;
begin
  Result := FVariables;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Terminal.SetSession(Value: TNsLibSSH2Session);
begin
  if FSession <> Value then
    FSession := Value;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Terminal.SetTerminal(Value: String);
begin
  if FTerminal <> Value then
    FTerminal := Value;
end;
   
//---------------------------------------------------------------------------

procedure TNsLibSSH2Terminal.SetVariables(Value: TStrings);
begin
  FVariables.Assign(Value);
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

function TExchangerThd.GetChannel: PLIBSSH2_CHANNEL;
begin
  Result := FChannel;
end;

//---------------------------------------------------------------------------

function TExchangerThd.GetExchangeSocket: TSocket;
begin
  Result := FExchangeSocket;
end;

//---------------------------------------------------------------------------

function TExchangerThd.GetPoolIndex: Integer;
begin
  Result := FPoolIndex;
end;
    
//---------------------------------------------------------------------------

function TExchangerThd.GetTerminated: Boolean;
begin
  Result := Self.Terminated;
end;

//---------------------------------------------------------------------------

procedure TExchangerThd.SetChannel(Value: PLIBSSH2_CHANNEL);
begin
  if FChannel <> Value then
    FChannel := Value;
end;

//---------------------------------------------------------------------------

procedure TExchangerThd.SetExchangeSocket(Value: TSocket);
begin
  if FExchangeSocket <> Value then
    FExchangeSocket := Value;
end;

//---------------------------------------------------------------------------

procedure TExchangerThd.SetPoolIndex(Value: Integer);
begin
  if FPoolIndex <> Value then
    FPoolIndex := Value;
end;

end.

