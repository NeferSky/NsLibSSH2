unit NsLibSSH2Session;

interface

uses
  Windows, SysUtils, Classes, WinSock, libssh2, NsLibSSH2Const;

type
  TAuthType = (atNone, atPassword, atPublicKey);

type
  TNsLibSSH2Session = class(TComponent)
  private
    FServerIP: String;
    FServerPort: Integer;
    FUsername: String;
    FPassword: String;
    FPublicKeyFile: String;
    FPrivateKeyFile: String;
    FAuthType: TAuthType;
    FOpened: Boolean;
    FStatus: String;
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
    function ConnectToServer: Boolean;
    function StartSSHSession: Boolean;
    function AuthOnServer: Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Open: Boolean;
    function OpenEx(AServerIP, AUserName, APassword,
      APublicKeyFile, APrivateKeyFile: String; AAuthType: TAuthType;
      AServerPort: Integer): Boolean;
    procedure Close;
    procedure CloseEx;
    property Session: PLIBSSH2_SESSION read FSession;
    property Fingerprint: PAnsiChar read FFingerprint;
    property UserAuth: PAnsiChar read FUserAuth;
  published
    property AfterCreate: TNotifyEvent read FAfterCreate write FAfterCreate;
    property BeforeDestroy: TNotifyEvent read FBeforeDestroy write FBeforeDestroy;
    property BeforeOpen: TNotifyEvent read FBeforeOpen write FBeforeOpen;
    property AfterOpen: TNotifyEvent read FAfterOpen write FAfterOpen;
    property BeforeClose: TNotifyEvent read FBeforeClose write FBeforeClose;
    property AfterClose: TNotifyEvent read FAfterClose write FAfterClose;
    property ServerIP: String read FServerIP write FServerIP;
    property ServerPort: Integer read FServerPort write FServerPort;
    property Username: String read FUsername write FUsername;
    property Password: String read FPassword write FPassword;
    property PublicKeyFile: String read FPublicKeyFile write FPublicKeyFile;
    property PrivateKeyFile: String read FPrivateKeyFile write FPrivateKeyFile;
    property AuthType: TAuthType read FAuthType write FAuthType default atNone;
    property Opened: Boolean read FOpened;
    property Status: String read FStatus;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('NeferSky', [TNsLibSSH2Session]);
end;

//---------------------------------------------------------------------------

{ TNsLibSSH2Session }

constructor TNsLibSSH2Session.Create(AOwner: TComponent);
var
  rc: Integer;
begin
  inherited Create(AOwner);

  FServerIP := VAL_EMPTY_STR;
  FServerPort := DEFAULT_SSH_PORT;
  FUsername := VAL_EMPTY_STR;
  FPassword := VAL_EMPTY_STR;
  FPublicKeyFile := VAL_EMPTY_STR;
  FPrivateKeyFile := VAL_EMPTY_STR;
  FAuthType := atNone;
  FOpened := VAL_FALSE;
  FFingerprint := VAL_EMPTY_STR;
  FUserAuth := VAL_EMPTY_STR;
  FStatus := ST_DISCONNECTED;
  FSession := nil;
  Auth := [];

  rc := WSAStartup(MAKEWORD(2,0), WSA_Data);
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

  if Assigned(AfterCreate) then AfterCreate(Self);
end;
  
//---------------------------------------------------------------------------

destructor TNsLibSSH2Session.Destroy;
begin
  if Assigned(BeforeDestroy) then BeforeDestroy(Self);

  if Opened then Close;

  libssh2_exit;
  WSACleanup;

  inherited Destroy;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Session.Open: Boolean;
begin
  if Assigned(BeforeOpen) then BeforeOpen(Self);

  Result := False;

  if Opened then Close;

  if not ConnectToServer then
    begin
      raise Exception.Create(FStatus);
    end;

  if not StartSSHSession then
    begin
      Close;
      raise Exception.Create(FStatus);
    end;

  if not AuthOnServer then
    begin
      Close;
      raise Exception.Create(FStatus);
    end;

  FStatus := ST_CONNECTED;
  FOpened := True;
  Result := Opened;

  if Assigned(AfterOpen) then AfterOpen(Self);
end;

//---------------------------------------------------------------------------

function TNsLibSSH2Session.OpenEx(AServerIP, AUserName, APassword,
  APublicKeyFile, APrivateKeyFile: String; AAuthType: TAuthType;
  AServerPort: Integer): Boolean;
begin
  Result := False;

  ServerIP := AServerIP;
  Username := AUserName;
  Password := APassword;
  ServerPort := AServerPort;
  PublicKeyFile := APublicKeyFile;
  PrivateKeyFile := APrivateKeyFile;
  AuthType := AAuthType;

  try
    Open;
  except
    Exit;
  end;

  Result := True;
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
  if ((INADDR_NONE = SockAddr.sin_addr.s_addr) and (INADDR_NONE = inet_addr(PAnsiChar(ServerIP)))) then
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
  FUserAuth := libssh2_userauth_list(FSession, PAnsiChar(Username), StrLen(PAnsiChar(Username)));

  if (Pos('password', FUserAuth) <> 0) then
    Include(Auth, AUTH_PASSWORD);
  if (Pos('publickey', FUserAuth) <> 0) then
    Include(Auth, AUTH_PUBLICKEY);

  if ((AuthType = atPublicKey) and (AUTH_PUBLICKEY in Auth)) then
    Auth := [AUTH_PUBLICKEY]
  else
    if ((AuthType = atPassword) and (AUTH_PASSWORD in Auth)) then
      Auth := [AUTH_PASSWORD]
    else
      begin
        FStatus := ER_AUTH_METHOD;
        Exit;
      end;

  if (Auth = [AUTH_PUBLICKEY]) then
    begin
      if (libssh2_userauth_publickey_fromfile(FSession, PAnsiChar(Username),
        PAnsiChar(PrivateKeyFile), PAnsiChar(PublicKeyFile), PAnsiChar(Password)) <> 0) then
        begin
          FStatus := ER_PUBKEY;
          Exit;
        end;
    end
  else
    if (Auth = [AUTH_PASSWORD]) then
      begin
        if (libssh2_userauth_password(FSession, PAnsiChar(Username), PAnsiChar(Password)) <> 0) then
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

  Result := True;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Session.CloseEx;
begin
  if Opened then Close;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Session.Close;
begin
  if Assigned(BeforeClose) then BeforeClose(Self);

  if FSession <> nil then
    begin
      libssh2_session_disconnect(FSession, ST_SESSION_CLOSED);
      libssh2_session_free(FSession);
      FSession := nil;
    end;

  if FSocket <> INVALID_SOCKET then
    CloseSocket(FSocket);

  FFingerprint := VAL_EMPTY_STR;
  FUserAuth := VAL_EMPTY_STR;
  FStatus := ST_DISCONNECTED;
  FOpened := False;

  if Assigned(AfterClose) then AfterClose(Self);
end;

//---------------------------------------------------------------------------

end.

