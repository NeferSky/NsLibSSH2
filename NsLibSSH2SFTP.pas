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
    property OwnerHandle: HWND read FOwnerHandle write FOwnerHandle;
    property FTPSession: PLIBSSH2_SFTP read FFTPSession write FFTPSession;
    property SrcFile: AnsiString read FSrcFile write FSrcFile;
    property DestFile: AnsiString read FDestFile write FDestFile;
  end;

type
  TFTPGetter = class(TFTPThread)
  public
    property OwnerHandle;
    property FTPSession;
    property SrcFile;
    property DestFile;
    procedure Execute; override;
  end;

type
  TFTPPutter = class(TFTPThread)
  public
    property OwnerHandle;
    property FTPSession;
    property SrcFile;
    property DestFile;
    procedure Execute; override;
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
    FBeforeTransfer: TNotifyEvent;
    FAfterTransfer: TNotifyEvent;
    FBeforeGet: TNotifyEvent;
    FAfterGet: TNotifyEvent;
    FBeforePut: TNotifyEvent;
    FAfterPut: TNotifyEvent;
    procedure GetterFree(Sender: TObject);
    procedure PutterFree(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Open: Boolean;
    procedure Close;
    procedure GetFile(SourceFile, DestinationFile: AnsiString);
    procedure PutFile(SourceFile, DestinationFile: AnsiString);
  published
    property AfterCreate: TNotifyEvent read FAfterCreate write FAfterCreate;
    property BeforeDestroy: TNotifyEvent read FBeforeDestroy write FBeforeDestroy;
    property BeforeOpen: TNotifyEvent read FBeforeOpen write FBeforeOpen;
    property AfterOpen: TNotifyEvent read FAfterOpen write FAfterOpen;
    property BeforeClose: TNotifyEvent read FBeforeClose write FBeforeClose;
    property AfterClose: TNotifyEvent read FAfterClose write FAfterClose;
    property BeforeTransfer: TNotifyEvent read FBeforeTransfer write FBeforeTransfer;
    property AfterTransfer: TNotifyEvent read FAfterTransfer write FAfterTransfer;
    property BeforeGet: TNotifyEvent read FBeforeGet write FBeforeGet;
    property AfterGet: TNotifyEvent read FAfterGet write FAfterGet;
    property BeforePut: TNotifyEvent read FBeforePut write FBeforePut;
    property AfterPut: TNotifyEvent read FAfterPut write FAfterPut;
    property Session: TNsLibSSH2Session read FSession write FSession;
    property Opened: Boolean read FOpened;
    property Status: string read FStatus;
    property GetInProgress: Boolean read FGetInProgress;
    property PutInProgress: Boolean read FPutInProgress;
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
  FFTPSession := nil;
  FFTPHandle := nil;
  FGetInProgress := False;
  FPutInProgress := False;
  FGetter := nil;
  FPutter := nil;
  FOpened := False;
  FStatus := ST_DISCONNECTED;

  if Assigned(AfterCreate) then AfterCreate(Self);
end;

//---------------------------------------------------------------------------

destructor TNsLibSSH2SFTP.Destroy;
begin
  if Assigned(BeforeDestroy) then BeforeDestroy(Self);

  if Opened then
    Close;

  inherited Destroy;
end;

//---------------------------------------------------------------------------

function TNsLibSSH2SFTP.Open: Boolean;
var
  SafeCounter: Integer;

begin
  if Assigned(BeforeOpen) then BeforeOpen(Self);

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

  if Assigned(AfterOpen) then AfterOpen(Self);
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2SFTP.Close;
begin
  if Assigned(BeforeClose) then BeforeClose(Self);

  if FFTPSession <> nil then
    begin
      libssh2_sftp_shutdown(FFTPSession);
      FFTPSession := nil;
    end;

  FStatus := ST_DISCONNECTED;
  FOpened := False;

  if Assigned(AfterClose) then AfterClose(Self);
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2SFTP.GetFile(SourceFile, DestinationFile: string);
var
  DestinationDir: string;
begin
  if Assigned(BeforeGet) then BeforeGet(Self);

  if GetInProgress then Exit;

  DestinationDir := ExtractFilePath(DestinationFile);
  if not DirectoryExists(DestinationDir) then
    raise Exception.Create(ER_DEST_NOT_EXISTS);

  if Assigned(BeforeTransfer) then BeforeTransfer(Self);

  FGetInProgress := True;

  FGetter := TFTPGetter.Create(True);
  FGetter.OnTerminate := GetterFree;
  FGetter.FreeOnTerminate := True;
  FGetter.FTPSession := FFTPSession;
  FGetter.SrcFile := SourceFile;
  FGetter.DestFile := DestinationFile;
  FGetter.Resume;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2SFTP.PutFile(SourceFile, DestinationFile: string);
begin
  if Assigned(BeforePut) then BeforePut(Self);

  if PutInProgress then Exit;

  if Assigned(BeforeTransfer) then BeforeTransfer(Self);

  FPutInProgress := True;

  FPutter := TFTPPutter.Create(True);
  FPutter.FreeOnTerminate := True;
  FPutter.OnTerminate := PutterFree;
  FPutter.FTPSession := FFTPSession;
  FPutter.SrcFile := SourceFile;
  FPutter.DestFile := DestinationFile;
  FPutter.Resume;
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2SFTP.GetterFree(Sender: TObject);
begin
//  FGetter.WaitFor;
//  FGetter.Free;
  FGetter := nil;
  FGetInProgress := False;
  if Assigned(AfterGet) then AfterGet(Self);
end;

//---------------------------------------------------------------------------

procedure TNsLibSSH2SFTP.PutterFree(Sender: TObject);
begin
  FPutInProgress := False;
//  FPutter.Free;
//  FPutter := nil;
  if Assigned(AfterPut) then AfterPut(Self);
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

  if (FFTPHandle = nil) then Terminate;

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
        if BytesReaded < 0 then Sleep(100);
      until (BytesReaded <> LIBSSH2_ERROR_EAGAIN) or (SafeCounter > MAX_CONNECTION_ATTEMPTS);

      if (BytesReaded > 0) then
        BlockWrite(TargetFile, Buffer, BytesReaded)
      else
        Break;
    end;
  until False;

  CloseFile(TargetFile);
  libssh2_sftp_close(FFTPHandle);
  FFTPHandle := nil;
  Self.Terminate;
  Self.DoTerminate;
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

  if (FFTPHandle = nil) then Terminate;

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
          until (BytesWritten = BytesReaded) or (SafeCounter > MAX_CONNECTION_ATTEMPTS);
        end;
    end;
  until BytesReaded < 1;

  CloseFile(TargetFile);
  libssh2_sftp_close(FFTPHandle);
end;

end.

