unit NsLibSSH2SFTP;

interface

uses
  Forms, Windows, Messages, SysUtils, Classes, WinSock, libssh2, libssh2_sftp,
  NsLibSSH2Session, NsLibSSH2Const;

type
  TFTPThread = class(TThread)
  private
    FOwnerHandle: HWND;
    FFTPSession: PLIBSSH2_SFTP;
    FFTPHandle: PLIBSSH2_SFTP_HANDLE;
    FSrcFile: AnsiString;
    FDestFile: AnsiString;

    // Property getters/setters
    function GetOwnerHandle: HWND;
    procedure SetOwnerHandle(Value: HWND);
    function GetFTPSession: PLIBSSH2_SFTP;
    procedure SetFTPSession(Value: PLIBSSH2_SFTP);
    function GetSrcFile: AnsiString;
    procedure SetSrcFile(Value: AnsiString);
    function GetDestFile: AnsiString;
    procedure SetDestFile(Value: AnsiString);

    property OwnerHandle: HWND read GetOwnerHandle write SetOwnerHandle;
    property FTPSession: PLIBSSH2_SFTP read GetFTPSession write SetFTPSession;
    property SrcFile: AnsiString read GetSrcFile write SetSrcFile;
    property DestFile: AnsiString read GetDestFile write SetDestFile;
  public
    procedure StartExchange(const SourceFile, DestinationFile: string);
  end;

type
  TFTPGetter = class(TFTPThread)
  public
    procedure Execute; override;
    property OwnerHandle;
    property FTPSession;
    property SrcFile;
    property DestFile;
  end;

type
  TFTPPutter = class(TFTPThread)
  public
    procedure Execute; override;
    property OwnerHandle;
    property FTPSession;
    property SrcFile;
    property DestFile;
  end;

type
  TNsLibSSH2SFTP = class(TComponent)
  private
    FSession: TNsLibSSH2Session;
    FFTPSession: PLIBSSH2_SFTP;
    FFTPHandle: PLIBSSH2_SFTP_HANDLE;
    FGetter: TFTPGetter;
    FPutter: TFTPPutter;
    FOpened: Boolean;
    FStatus: string;
    FGetInProgress: Boolean;
    FPutInProgress: Boolean;
    //Events
    FAfterCreate: TNotifyEvent;
    FBeforeDestroy: TNotifyEvent;
    FBeforeOpen: TNotifyEvent;
    FAfterOpen: TNotifyEvent;
    FBeforeClose: TNotifyEvent;
    FAfterClose: TNotifyEvent;
    FBeforeGet: TNotifyEvent;
    FAfterGet: TNotifyEvent;
    FBeforePut: TNotifyEvent;
    FAfterPut: TNotifyEvent;

    procedure GetterEnd(Sender: TObject);
    procedure PutterEnd(Sender: TObject);

    // Property getters/setters
    function GetSession: TNsLibSSH2Session;
    procedure SetSession(Value: TNsLibSSH2Session);
    function GetOpened: Boolean;
    function GetStatus: string;
    function GetGetInProgress: Boolean;
    function GetPutInProgress: Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Open: Boolean;
    procedure Close;
    procedure GetFile(const SourceFile, DestinationFile: AnsiString);
    procedure PutFile(const SourceFile, DestinationFile: AnsiString);
  published
    property AfterCreate: TNotifyEvent read FAfterCreate write FAfterCreate;
    property BeforeDestroy: TNotifyEvent read FBeforeDestroy write
      FBeforeDestroy;
    property BeforeOpen: TNotifyEvent read FBeforeOpen write FBeforeOpen;
    property AfterOpen: TNotifyEvent read FAfterOpen write FAfterOpen;
    property BeforeClose: TNotifyEvent read FBeforeClose write FBeforeClose;
    property AfterClose: TNotifyEvent read FAfterClose write FAfterClose;
    property BeforeGet: TNotifyEvent read FBeforeGet write FBeforeGet;
    property AfterGet: TNotifyEvent read FAfterGet write FAfterGet;
    property BeforePut: TNotifyEvent read FBeforePut write FBeforePut;
    property AfterPut: TNotifyEvent read FAfterPut write FAfterPut;
    property Session: TNsLibSSH2Session read GetSession write SetSession;
    property Opened: Boolean read GetOpened;
    property Status: string read GetStatus;
    property GetInProgress: Boolean read GetGetInProgress;
    property PutInProgress: Boolean read GetPutInProgress;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('NeferSky', [TNsLibSSH2SFTP]);
end;

//---------------------------------------------------------------------------

{ TNsLibSSH2SFTP }
// Public

constructor TNsLibSSH2SFTP.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FSession := nil;
  FFTPSession := nil;
  FFTPHandle := nil;
  FGetInProgress := False;
  FPutInProgress := False;

  FPutter := nil;
  FOpened := False;
  FStatus := ST_DISCONNECTED;

  if Assigned(AfterCreate) then
    AfterCreate(Self);
end;

//---------------------------------------------------------------------------

destructor TNsLibSSH2SFTP.Destroy;
begin
  if Assigned(BeforeDestroy) then
    BeforeDestroy(Self);

  if Opened then
    Close;

  inherited Destroy;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2SFTP.Open: Boolean;
var
  SafeCounter: Integer;

begin
  if Assigned(BeforeOpen) then
    BeforeOpen(Self);

  Result := False;

  if FSession = nil then
  begin
    FStatus := ER_SESSION_UNAVAILABLE;
    Exit;
  end;

  // Unclear why the channel is not created by the first time,
  // that's why i have to make several attempts.
  // I use the SafeCounter to prevent an infinite loop.
  SafeCounter := 0;
  repeat
    Inc(SafeCounter);
    FFTPSession := libssh2_sftp_init(FSession.Session);
    // Just waiting. It's a kind of magic.
    Sleep(1000);
  until (FFTPSession <> nil) or (SafeCounter > MAX_CONNECTION_ATTEMPTS);

  if (FFTPSession = nil) then
  begin
    FStatus := ER_FTP_OPEN;
    Exit;
  end;

  FStatus := ST_CONNECTED;
  FOpened := True;
  Result := Opened;

  if Assigned(AfterOpen) then
    AfterOpen(Self);
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2SFTP.Close;
begin
  if Assigned(BeforeClose) then
    BeforeClose(Self);

  if FFTPSession <> nil then
  begin
    libssh2_sftp_shutdown(FFTPSession);
    FFTPSession := nil;
  end;

  FStatus := ST_DISCONNECTED;
  FOpened := False;

  if Assigned(AfterClose) then
    AfterClose(Self);
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2SFTP.GetFile(const SourceFile, DestinationFile: string);
var
  DestinationDir: string;
begin
  if Assigned(BeforeGet) then
    BeforeGet(Self);

  if GetInProgress then
    Exit;

  DestinationDir := ExtractFilePath(DestinationFile);
  if not DirectoryExists(DestinationDir) then
    raise Exception.Create(ER_DEST_NOT_EXISTS);

  FGetInProgress := True;

  FGetter := TFTPGetter.Create(True);
  FGetter.OnTerminate := GetterEnd;
  FGetter.FTPSession := FFTPSession;
  FGetter.StartExchange(SourceFile, DestinationFile);
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2SFTP.PutFile(const SourceFile, DestinationFile: string);
begin
  if Assigned(BeforePut) then
    BeforePut(Self);

  if PutInProgress then
    Exit;

  FPutInProgress := True;

  FPutter := TFTPPutter.Create(True);
  FPutter.OnTerminate := PutterEnd;
  FPutter.FTPSession := FFTPSession;
  FPutter.StartExchange(SourceFile, DestinationFile);
end;

//---------------------------------------------------------------------------
// Private

procedure TNsLibSSH2SFTP.GetterEnd(Sender: TObject);
begin
  FGetInProgress := False;
  if Assigned(AfterGet) then
    AfterGet(Self);
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2SFTP.PutterEnd(Sender: TObject);
begin
  FPutInProgress := False;
  if Assigned(AfterPut) then
    AfterPut(Self);
end;

//---------------------------------------------------------------------------

function TNsLibSSH2SFTP.GetGetInProgress: Boolean;
begin
  Result := FGetInProgress;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2SFTP.GetOpened: Boolean;
begin
  Result := FOpened;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2SFTP.GetPutInProgress: Boolean;
begin
  Result := FPutInProgress;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2SFTP.GetSession: TNsLibSSH2Session;
begin
  Result := FSession;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2SFTP.GetStatus: string;
begin
  Result := FStatus;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2SFTP.SetSession(Value: TNsLibSSH2Session);
begin
  if FSession <> Value then
    FSession := Value;
end;

//---------------------------------------------------------------------------

{ TFTPGetter }

procedure TFTPGetter.Execute;
var
  Buffer: array[1..1024] of Char;
  BytesReaded: Integer;
  TargetFile: file;
  SafeCounter: Integer;
begin
  // Unclear why the channel is not created by the first time,
  // that's why i have to make several attempts.
  // I use the SafeCounter to prevent an infinite loop.
  SafeCounter := 0;
  repeat
    Inc(SafeCounter);
    FFTPHandle := libssh2_sftp_open(FFTPSession, PAnsiChar(FSrcFile),
      LIBSSH2_FXF_READ, 0);
    // Just waiting. It's a kind of magic.
    Sleep(1000);
  until (FFTPHandle <> nil) or (SafeCounter > MAX_CONNECTION_ATTEMPTS);

  if (FFTPHandle = nil) then
    Terminate;

  AssignFile(TargetFile, FDestFile);
  ReWrite(TargetFile, 1);

  repeat
    begin
      FillChar(Buffer, SizeOf(Buffer), #0);
      SafeCounter := 0;

      repeat
        Inc(SafeCounter);
        BytesReaded := libssh2_sftp_read(FFTPHandle, @Buffer, SizeOf(Buffer));
        // Just waiting. It's a kind of magic.
        if BytesReaded < 0 then
          Sleep(100);
      until (BytesReaded <> LIBSSH2_ERROR_EAGAIN) or (SafeCounter >
        MAX_CONNECTION_ATTEMPTS);

      if (BytesReaded > 0) then
        BlockWrite(TargetFile, Buffer, BytesReaded)
      else
        Break;
    end;
  until Terminated;

  CloseFile(TargetFile);
  libssh2_sftp_close(FFTPHandle);
  FFTPHandle := nil;
end;

//---------------------------------------------------------------------------

{ TFTPPutter }

procedure TFTPPutter.Execute;
var
  Buffer: array[1..1024] of Char;
  BytesReaded, BytesWritten: Integer;
  TargetFile: file;
  SafeCounter: Integer;

  procedure AnalyseSendingResult;
  begin
    if BytesWritten < BytesReaded then
    begin
      if (BytesWritten <> LIBSSH2_ERROR_EAGAIN) then
        BytesReaded := BytesReaded - BytesWritten
      else
      begin
        Inc(SafeCounter);
        Sleep(100);
      end;
    end;
  end;

begin
  // Unclear why the channel is not created by the first time,
  // that's why i have to make several attempts.
  // I use the SafeCounter to prevent an infinite loop.
  SafeCounter := 0;
  repeat
    Inc(SafeCounter);
    FFTPHandle := libssh2_sftp_open(FFTPSession, PAnsiChar(FDestFile),
      (LIBSSH2_FXF_WRITE or LIBSSH2_FXF_CREAT or LIBSSH2_FXF_TRUNC),
      (LIBSSH2_SFTP_S_IRUSR or LIBSSH2_SFTP_S_IWUSR or LIBSSH2_SFTP_S_IRGRP or
      LIBSSH2_SFTP_S_IROTH));
    // Just waiting. It's a kind of magic.
    Sleep(1000);
  until (FFTPHandle <> nil) or (SafeCounter > MAX_CONNECTION_ATTEMPTS);

  if (FFTPHandle = nil) then
    Terminate;

  AssignFile(TargetFile, FSrcFile);
  ReSet(TargetFile, 1);
  BytesReaded := 0;

  repeat
    begin
      FillChar(Buffer, SizeOf(Buffer), #0);
      BlockRead(TargetFile, Buffer, SizeOf(Buffer), BytesReaded);

      if (BytesReaded > 0) then
      begin
        SafeCounter := 1;
        repeat
          BytesWritten := libssh2_sftp_write(FFTPHandle, @Buffer, BytesReaded);
          AnalyseSendingResult;
        until (BytesWritten = BytesReaded) or (SafeCounter >
          MAX_CONNECTION_ATTEMPTS);
      end;
    end;
  until (BytesReaded < 1) or Terminated;

  CloseFile(TargetFile);
  libssh2_sftp_close(FFTPHandle);
end;

//---------------------------------------------------------------------------

{ TFTPThread }

procedure TFTPThread.StartExchange(const SourceFile, DestinationFile: string);
begin
  SrcFile := SourceFile;
  DestFile := DestinationFile;
  Resume;
end;

//---------------------------------------------------------------------------

function TFTPThread.GetDestFile: AnsiString;
begin
  Result := FDestFile;
end;

//---------------------------------------------------------------------------

function TFTPThread.GetFTPSession: PLIBSSH2_SFTP;
begin
  Result := FFTPSession;
end;

//---------------------------------------------------------------------------

function TFTPThread.GetOwnerHandle: HWND;
begin
  Result := FOwnerHandle;
end;

//---------------------------------------------------------------------------

function TFTPThread.GetSrcFile: AnsiString;
begin
  Result := FSrcFile;
end;

//---------------------------------------------------------------------------

procedure TFTPThread.SetDestFile(Value: AnsiString);
begin
  if FDestFile <> Value then
    FDestFile := Value;
end;

//---------------------------------------------------------------------------

procedure TFTPThread.SetFTPSession(Value: PLIBSSH2_SFTP);
begin
  if FFTPSession <> Value then
    FFTPSession := Value;
end;

//---------------------------------------------------------------------------

procedure TFTPThread.SetOwnerHandle(Value: HWND);
begin
  if FOwnerHandle <> Value then
    FOwnerHandle := Value;
end;

//---------------------------------------------------------------------------

procedure TFTPThread.SetSrcFile(Value: AnsiString);
begin
  if FSrcFile <> Value then
    FSrcFile := Value;
end;

end.

