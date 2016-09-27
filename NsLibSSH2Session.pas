unit NsLibSSH2Session;

interface

uses
  Windows, SysUtils, Classes, WinSock, libssh2, NsLibSSH2Const;

type
  TAuthType = (atNone, atPassword, atPublicKey);

type
  TNsLibSSH2Session = class(TComponent)
  private
    FServerIP: string;
    FServerPort: Integer;
    FUsername: string;
    FPassword: string;
    FPublicKeyFile: string;
    FPrivateKeyFile: string;
    FAuthType: TAuthType;
    FOpened: Boolean;
    FStatus: string;
    FFingerprint: PAnsiChar;
    FUserAuth: PAnsiChar;

    FSocket: TSocket;
    FSession: PLIBSSH2_SESSION;
    Auth: set of Byte;
    SockAddr: sockaddr_in;
    WSA_Data: WSAData;

    //Events
    FAfterCreate: TNotifyEvent;
    FBeforeDestroy: TNotifyEvent;
    FBeforeOpen: TNotifyEvent;
    FAfterOpen: TNotifyEvent;
    FBeforeClose: TNotifyEvent;
    FAfterClose: TNotifyEvent;
  protected
    procedure InitProperties;
    function ConnectToServer: Boolean;
    function StartSSHSession: Boolean;
    function AuthOnServer: Boolean;

    // Property getters/setters
    function GetSession: PLIBSSH2_SESSION;
    function GetFingerprint: PAnsiChar;
    function GetUserAuth: PAnsiChar;
    function GetServerIP: string;
    procedure SetServerIP(Value: string);
    function GetServerPort: Integer;
    procedure SetServerPort(Value: Integer);
    function GetUsername: string;
    procedure SetUsername(Value: string);
    function GetPassword: string;
    procedure SetPassword(Value: string);
    function GetPublicKeyFile: string;
    procedure SetPublicKeyFile(Value: string);
    function GetPrivateKeyFile: string;
    procedure SetPrivateKeyFile(Value: string);
    function GetAuthType: TAuthType;
    procedure SetAuthType(Value: TAuthType);
    function GetOpened: Boolean;
    function GetStatus: string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Open: Boolean;
    function OpenEx(const AServerIP, AUserName, APassword,
      APublicKeyFile, APrivateKeyFile: string; AAuthType: TAuthType;
      AServerPort: Integer): Boolean;
    procedure Close;
    property Session: PLIBSSH2_SESSION read GetSession;
    property Fingerprint: PAnsiChar read GetFingerprint;
    property UserAuth: PAnsiChar read GetUserAuth;
  published
    property AfterCreate: TNotifyEvent read FAfterCreate write FAfterCreate;
    property BeforeDestroy: TNotifyEvent read FBeforeDestroy write
      FBeforeDestroy;
    property BeforeOpen: TNotifyEvent read FBeforeOpen write FBeforeOpen;
    property AfterOpen: TNotifyEvent read FAfterOpen write FAfterOpen;
    property BeforeClose: TNotifyEvent read FBeforeClose write FBeforeClose;
    property AfterClose: TNotifyEvent read FAfterClose write FAfterClose;
    property ServerIP: string read GetServerIP write SetServerIP;
    property ServerPort: Integer read GetServerPort write SetServerPort;
    property Username: string read GetUsername write SetUsername;
    property Password: string read GetPassword write SetPassword;
    property PublicKeyFile: string read GetPublicKeyFile write SetPublicKeyFile;
    property PrivateKeyFile: string read GetPrivateKeyFile write
      SetPrivateKeyFile;
    property AuthType: TAuthType read GetAuthType write SetAuthType default
      atNone;
    property Opened: Boolean read GetOpened;
    property Status: string read GetStatus;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('NeferSky', [TNsLibSSH2Session]);
end;

//---------------------------------------------------------------------------

{ TNsLibSSH2Session }
// Public

constructor TNsLibSSH2Session.Create(AOwner: TComponent);
var
  rc: Integer;
begin
  inherited Create(AOwner);

  InitProperties;

  rc := WSAStartup(MAKEWORD(2, 0), WSA_Data);
  if (rc <> 0) then
  begin
    raise Exception.CreateFmt(ER_WSAERROR, [rc]);
    Exit;
  end;

  rc := libssh2_init(0);
  if (rc <> 0) then
  begin
    raise Exception.CreateFmt(ER_LIBSSH2_INIT, [rc]);
    Exit;
  end;

  if Assigned(AfterCreate) then
    AfterCreate(Self);
end;

//---------------------------------------------------------------------------

destructor TNsLibSSH2Session.Destroy;
begin
  if Assigned(BeforeDestroy) then
    BeforeDestroy(Self);

  if Opened then
    Close;

  libssh2_exit;
  WSACleanup;

  inherited Destroy;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Session.Open: Boolean;
begin
  if Assigned(BeforeOpen) then
    BeforeOpen(Self);

  Result := False;

  if Opened then
    Close;

  if not ConnectToServer then
    Exit;

  if not StartSSHSession then
  begin
    Close;
    Exit;
  end;

  if not AuthOnServer then
  begin
    Close;
    Exit;
  end;

  FStatus := ST_CONNECTED;
  FOpened := True;
  Result := Opened;

  if Assigned(AfterOpen) then
    AfterOpen(Self);
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Session.OpenEx(const AServerIP, AUserName, APassword,
  APublicKeyFile, APrivateKeyFile: string; AAuthType: TAuthType;
  AServerPort: Integer): Boolean;
begin
  ServerIP := AServerIP;
  Username := AUserName;
  Password := APassword;
  ServerPort := AServerPort;
  PublicKeyFile := APublicKeyFile;
  PrivateKeyFile := APrivateKeyFile;
  AuthType := AAuthType;

  Result := Open;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Session.Close;
begin
  if Assigned(BeforeClose) then
    BeforeClose(Self);

  if FSession <> nil then
  begin
    libssh2_session_disconnect(FSession, ST_SESSION_CLOSED);
    libssh2_session_free(FSession);
    FSession := nil;
  end;

  if FSocket <> INVALID_SOCKET then
    CloseSocket(FSocket);

  FFingerprint := DEFAULT_EMPTY_STR;
  FUserAuth := DEFAULT_EMPTY_STR;
  FStatus := ST_DISCONNECTED;
  FOpened := False;

  if Assigned(AfterClose) then
    AfterClose(Self);
end;

//---------------------------------------------------------------------------
// Protected

procedure TNsLibSSH2Session.InitProperties;
begin
  FServerIP := DEFAULT_EMPTY_STR;
  FServerPort := DEFAULT_SSH_PORT;
  FUsername := DEFAULT_EMPTY_STR;
  FPassword := DEFAULT_EMPTY_STR;
  FPublicKeyFile := DEFAULT_EMPTY_STR;
  FPrivateKeyFile := DEFAULT_EMPTY_STR;
  FAuthType := atNone;
  FOpened := False;
  FFingerprint := DEFAULT_EMPTY_STR;
  FUserAuth := DEFAULT_EMPTY_STR;
  FStatus := ST_DISCONNECTED;
  FSession := nil;
  Auth := [];
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Session.ConnectToServer: Boolean;
begin
  Result := False;

  FSocket := Socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (FSocket = INVALID_SOCKET) then
  begin
    FStatus := ER_OPEN_SOCKET;
    Exit;
  end;

  SockAddr.sin_family := AF_INET;
  SockAddr.sin_addr.s_addr := inet_addr(PAnsiChar(ServerIP));
  if ((INADDR_NONE = SockAddr.sin_addr.s_addr) and (INADDR_NONE =
    inet_addr(PAnsiChar(ServerIP)))) then
  begin
    FStatus := ER_IP_INCORRECT;
    Exit;
  end;

  SockAddr.sin_port := htons(ServerPort);
  if (Connect(FSocket, SockAddr, SizeOf(sockaddr_in)) <> 0) then
  begin
    FStatus := ER_CONNECT;
    Exit;
  end;

  Result := True;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Session.StartSSHSession: Boolean;
var
  rc: Integer;
begin
  Result := False;

  FSession := libssh2_session_init;
  if (FSession = nil) then
  begin
    FStatus := ER_SESSION_INIT;
    Exit;
  end;

  rc := libssh2_session_handshake(FSession, FSocket);
  if (rc <> 0) then
  begin
    FStatus := Format(ER_SESSION_START, [rc]);
    Exit;
  end;

  Result := True;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Session.AuthOnServer: Boolean;
begin
  Result := False;

  FFingerprint := libssh2_hostkey_hash(FSession, LIBSSH2_HOSTKEY_HASH_SHA1);
  FUserAuth := libssh2_userauth_list(FSession, PAnsiChar(Username),
    StrLen(PAnsiChar(Username)));

  if (Pos('password', FUserAuth) <> 0) then
    Include(Auth, AUTH_PASSWORD);
  if (Pos('publickey', FUserAuth) <> 0) then
    Include(Auth, AUTH_PUBLICKEY);

  if ((AuthType = atPublicKey) and (AUTH_PUBLICKEY in Auth)) then
    Auth := [AUTH_PUBLICKEY]
  else if ((AuthType = atPassword) and (AUTH_PASSWORD in Auth)) then
    Auth := [AUTH_PASSWORD]
  else
  begin
    FStatus := ER_AUTH_METHOD;
    Exit;
  end;

  if (Auth = [AUTH_PUBLICKEY]) then
  begin
    if (libssh2_userauth_publickey_fromfile(FSession, PAnsiChar(Username),
      PAnsiChar(PublicKeyFile), PAnsiChar(PrivateKeyFile), PAnsiChar(Password))
        <> 0) then
    begin
      FStatus := ER_PUBKEY;
      Exit;
    end;
  end
  else if (Auth = [AUTH_PASSWORD]) then
  begin
    if (libssh2_userauth_password(FSession, PAnsiChar(Username),
      PAnsiChar(Password)) <> 0) then
    begin
      FStatus := ER_PASSWORD;
      Exit;
    end;
  end
  else
  begin
    FStatus := ER_AUTH_METHOD;
    Exit;
  end;

  libssh2_session_set_blocking(FSession, 0);
  Result := True;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Session.GetAuthType: TAuthType;
begin
  Result := FAuthType;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Session.GetFingerprint: PAnsiChar;
begin
  Result := FFingerprint;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Session.GetOpened: Boolean;
begin
  Result := FOpened;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Session.GetPassword: string;
begin
  Result := FPassword;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Session.GetPrivateKeyFile: string;
begin
  Result := FPrivateKeyFile;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Session.GetPublicKeyFile: string;
begin
  Result := FPublicKeyFile;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Session.GetServerIP: string;
begin
  Result := FServerIP;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Session.GetServerPort: Integer;
begin
  Result := FServerPort;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Session.GetSession: PLIBSSH2_SESSION;
begin
  Result := FSession;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Session.GetStatus: string;
begin
  Result := FStatus;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Session.GetUserAuth: PAnsiChar;
begin
  Result := FUserAuth;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Session.GetUsername: string;
begin
  Result := FUsername;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Session.SetAuthType(Value: TAuthType);
begin
  if FAuthType <> Value then
    FAuthType := Value;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Session.SetPassword(Value: string);
begin
  if FPassword <> Value then
    FPassword := Value;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Session.SetPrivateKeyFile(Value: string);
begin
  if FPrivateKeyFile <> Value then
    FPrivateKeyFile := Value;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Session.SetPublicKeyFile(Value: string);
begin
  if FPublicKeyFile <> Value then
    FPublicKeyFile := Value;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Session.SetServerIP(Value: string);
begin
  if FServerIP <> Value then
    FServerIP := Value;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Session.SetServerPort(Value: Integer);
begin
  if FServerPort <> Value then
    FServerPort := Value;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Session.SetUsername(Value: string);
begin
  if FUsername <> Value then
    FUsername := Value;
end;

end.

