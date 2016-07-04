unit NsLibSSH2Session;

{
  version 1.1
}

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

    FSock: TSocket;
    FSession: PLIBSSH2_SESSION;

    rc: Integer;
    Auth: set of Byte;
    SockAddr: sockaddr_in;
    WSA_Data: WSAData;
  protected
    function ConnectToServer: Boolean;
    function StartSSHSession: Boolean;
    function AuthOnServer: Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Open: Boolean;
    procedure Close;
    property Session: PLIBSSH2_SESSION read FSession;
    property Fingerprint: PAnsiChar read FFingerprint;
    property UserAuth: PAnsiChar read FUserAuth;
  published
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

{
type
  TTermExchangeThd = class(TThread)
  private
    FSock: TSocket;
    FChannel: PLIBSSH2_CHANNEL;
  public
    property Sock: TSocket read FSock write FSock;
    property Channel: PLIBSSH2_CHANNEL read FChannel write FChannel;
    procedure Execute; override;
    destructor Destroy; override;
  end;

type
  TNsLibSSH2Terminal = class(TComponent)
  private
    FSession: TNsLibSSH2Session;
    FChannel: PLIBSSH2_CHANNEL;
    FExchangeThd: TTermExchangeThd;
    FOpened: Boolean;
    FStatus: String;
    FWeRead, RWeSend: String;
  protected
    //
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Open: Boolean;
    procedure Close;
  published
    property Session: TNsLibSSH2Session read FSession write FSession;
  end;
 }
procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('NeferSky', [TNsLibSSH2Session]);
end;

//---------------------------------------------------------------------------

{ TNsLibSSH2Session }

constructor TNsLibSSH2Session.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FServerIP := '';
  FServerPort := 22;
  FUsername := '';
  FPassword := '';
  FPublicKeyFile := '';
  FPrivateKeyFile := '';
  FAuthType := atNone;
  FOpened := False;
  FFingerprint := '';
  FUserAuth := '';
  FStatus := 'Disconnected';
  FSession := nil;
  Auth := [];

  rc := WSAStartup(MAKEWORD(2,0), WSA_Data);
  if (rc <> 0) then
    begin
      raise Exception.CreateFmt('WSAStartup failed with error: %d', [rc]);
      Exit;
    end;

  rc := libssh2_init(0);
  if (rc <> 0) then
    begin
      raise Exception.CreateFmt('libssh2 initialization failed (%d)', [rc]);
      Exit;
    end;
end;
  
//---------------------------------------------------------------------------

destructor TNsLibSSH2Session.Destroy;
begin
  if Opened then Close;

  libssh2_exit;
  WSACleanup;

  inherited Destroy;
end;
   
//---------------------------------------------------------------------------

function TNsLibSSH2Session.Open: Boolean;
begin
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

  FStatus := 'Connected';
  FOpened := True;
  Result := Opened;
end;
   
//---------------------------------------------------------------------------

function TNsLibSSH2Session.ConnectToServer: Boolean;
begin
  Result := False;

  FSock := Socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (FSock = INVALID_SOCKET) then
    begin
      FStatus := 'Failed to open socket';
      Exit;
    end;

  SockAddr.sin_family := AF_INET;
  SockAddr.sin_addr.s_addr := inet_addr(PAnsiChar(ServerIP));
  if ((INADDR_NONE = SockAddr.sin_addr.s_addr) and (INADDR_NONE = inet_addr(PAnsiChar(ServerIP)))) then
    begin
      FStatus := 'IP address is wrong';
      Exit;
    end;

  SockAddr.sin_port := htons(ServerPort);
  if (Connect(FSock, SockAddr, SizeOf(sockaddr_in)) <> 0) then
    begin
      FStatus := 'Failed to connect to server';
      Exit;
    end;

  Result := True;
end;
   
//---------------------------------------------------------------------------

function TNsLibSSH2Session.StartSSHSession: Boolean;
begin
  Result := False;

  FSession := libssh2_session_init;
  if (FSession = nil) then
    begin
      FStatus := 'Could not initialize SSH session';
      Exit;
    end;

  rc := libssh2_session_handshake(FSession, FSock);
  if (rc <> 0) then
    begin
      FStatus := Format('Error when starting up SSH session: %d', [rc]);
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
        FStatus := 'No supported authentication methods found';
        Exit;
      end;

  if (Auth = [AUTH_PUBLICKEY]) then
    begin
      if (libssh2_userauth_publickey_fromfile(FSession, PAnsiChar(Username),
        PAnsiChar(PrivateKeyFile), PAnsiChar(PublicKeyFile), PAnsiChar(Password)) <> 0) then
        begin
          FStatus := 'Authentication by public key failed';
          Exit;
        end;
    end
  else
    if (Auth = [AUTH_PASSWORD]) then
      begin
        if (libssh2_userauth_password(FSession, PAnsiChar(Username), PAnsiChar(Password)) <> 0) then
          begin
            FStatus := 'Authentication by password failed';
            Exit;
          end;
      end
    else
      begin
        FStatus := 'No supported authentication methods found';
        Exit;
      end;

  Result := True;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2Session.Close;
begin
  if FSession <> nil then
    begin
      libssh2_session_disconnect(FSession, 'Session disconnect');
      libssh2_session_free(FSession);
    end;

  if FSock <> INVALID_SOCKET then
    CloseSocket(FSock);

  FFingerprint := '';
  FUserAuth := '';
  FStatus := 'Disconnected';
  FOpened := False;
end;

//---------------------------------------------------------------------------

end.

