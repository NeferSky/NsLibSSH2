unit NsLibSSH2SFTP;

interface

uses
  Windows, SysUtils, Classes, WinSock, libssh2, libssh2_sftp, NsLibSSH2Session,
    NsLibSSH2Const;

type
  TNsLibSSH2SFTP = class(TComponent)
  private
    FSession: TNsLibSSH2Session;
    FFTPSession: PLIBSSH2_SFTP;
    FFTPHandle: PLIBSSH2_SFTP_HANDLE;
//    FListenThd: TThread; //TChanListenThd;
    FOpened: Boolean;
    FStatus: String;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Open: Boolean;
    procedure Close;
    procedure GetFile(PathOnServer: String);
    procedure PutFile(PathOnServer: String);
  published
    property Session: TNsLibSSH2Session read FSession write FSession;
    property Opened: Boolean read FOpened;
    property Status: String read FStatus;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('NeferSky', [TNsLibSSH2SFTP]);
end;

//---------------------------------------------------------------------------

{ TNsLibSSH2SFTP }

constructor TNsLibSSH2SFTP.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FSession := nil;
  FOpened := False;
  FStatus := 'Disconnected';
end;

//---------------------------------------------------------------------------

destructor TNsLibSSH2SFTP.Destroy;
begin
  if Opened then Close;

  inherited Destroy;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2SFTP.Open: Boolean;
begin
  Result := False;

  if FSession = nil then
    raise Exception.Create('Session is not available');

  FFTPSession := libssh2_sftp_init(FSession.Session);
  if (FFTPSession = nil) then
  begin
    FStatus := 'Unable to open SFTP session';
    Exit;
  end;

  FStatus := 'Connected';
  FOpened := True;
  Result := Opened;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2SFTP.Close;
begin
  libssh2_sftp_close(FFTPHandle);
  libssh2_sftp_shutdown(FFTPSession);

  FStatus := 'Disconnected';
  FOpened := False;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2SFTP.GetFile(PathOnServer: String);
var
  mem: Array[1..1024] of Char;
  rc: Integer;
begin

  FFTPHandle := libssh2_sftp_open(FFTPSession, PAnsiChar(PathOnServer), LIBSSH2_FXF_READ, 0);
  if (FFTPHandle = nil) then
  begin
    FStatus := ('Unable to open file with SFTP: ' +
      IntToStr(libssh2_sftp_last_error(FFTPSession)));
    Exit;
  end;

  repeat
    begin
      rc := libssh2_sftp_read(FFTPHandle, @mem, sizeof(mem));

      if (rc > 0) then
//        write(1, mem, rc)
      else
        Break;
    end;
  until False;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2SFTP.PutFile(PathOnServer: String);
var
  mem: Array[1..1024] of Char;
  rc: Integer;
begin

  FFTPHandle := libssh2_sftp_open(FFTPSession, PAnsiChar(PathOnServer), LIBSSH2_FXF_WRITE, 0);
  if (FFTPHandle = nil) then
  begin
    FStatus := ('Unable to open file with SFTP: ' +
      IntToStr(libssh2_sftp_last_error(FFTPSession)));
    Exit;
  end;

  repeat
    begin
      rc := libssh2_sftp_write(FFTPHandle, @mem, sizeof(mem));

      if (rc > 0) then
//        write(1, mem, rc)
      else
        Break;
    end;
  until False;
end;

//---------------------------------------------------------------------------

end.

