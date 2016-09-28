unit NsCryptoLibSSHTerminal;

interface

uses
  StdCtrls, SysUtils, Classes, DelphiCryptlib, cryptlib, NsLibSSH2Session, NsLibSSH2Const;

type
  TNsCryptoLibSSHTerminal = class(TCustomMemo)
  private
    FSession: TNsLibSSH2Session;
    FCryptoSSH: TCryptSession;
    FOpened: Boolean;
    FStatus: string;
    LenData: Integer;
    Data: array [0..255] of AnsiChar;

    function Connect: Boolean;
    procedure KeyboardProc(Sender: TObject; var Key: Char);
    procedure DoSendBuffer;
    procedure DoRecvBuffer;

    // Property getters/setters
    function GetSession: TNsLibSSH2Session;
    procedure SetSession(Value: TNsLibSSH2Session);
    function GetOpened: Boolean;
    function GetStatus: string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Open: Boolean;
    procedure Close;
    property Session: TNsLibSSH2Session read GetSession write SetSession;
    property Opened: Boolean read GetOpened;
    property Status: string read GetStatus;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('NeferSky', [TNsCryptoLibSSHTerminal]);
end;

//---------------------------------------------------------------------------

{ TNsCryptoLibSSHTerminal }
// Public

constructor TNsCryptoLibSSHTerminal.Create(AOwner: TComponent);
begin
  inherited;

  OnKeyPress := KeyboardProc;
  FSession := nil;
  FOpened := False;
  FStatus := ST_DISCONNECTED;
end;

//---------------------------------------------------------------------------

destructor TNsCryptoLibSSHTerminal.Destroy;
begin
  if Opened then
    Close;

  inherited;
end;

//---------------------------------------------------------------------------

function TNsCryptoLibSSHTerminal.Open: Boolean;
begin
  Result := False;

  Connect;
  if FCryptoSSH = nil then Exit;
  FCryptoSSH.FlushData;

  LenData := 255;
  FCryptoSSH.PopData(@Data, LenData);
  Self.Lines.Add(Data);

  FStatus := ST_CONNECTED;
  FOpened := True;
  Result := Opened;
end;

//---------------------------------------------------------------------------

procedure TNsCryptoLibSSHTerminal.Close;
begin
  FreeAndNil(FCryptoSSH);

  FStatus := ST_DISCONNECTED;
  FOpened := False;
end;

//---------------------------------------------------------------------------
// Private

function TNsCryptoLibSSHTerminal.Connect: Boolean;
begin
  Result := False;

  FCryptoSSH := TCryptSession.Create(CRYPT_SESSION_SSH);

  with FCryptoSSH do
  begin
    ServerName := FSession.ServerIP;
    UserName := FSession.Username;
    Password := FSession.Password;
  end;

  try
    FCryptoSSH.Activate;
    Result := True;
  except
    on E: ECryptError do
      FreeAndNil(FCryptoSSH);
  end;
end;

//---------------------------------------------------------------------------

procedure TNsCryptoLibSSHTerminal.KeyboardProc(Sender: TObject; var Key: Char);
begin
  Inc(LenData);
  Data[LenData] := Key;
  if Key = #13 then
    begin
      DoSendBuffer;
      DoRecvBuffer;
      FillChar(Data, SizeOf(Data), #0);
      LenData := 0;
    end;
end;

//---------------------------------------------------------------------------

procedure TNsCryptoLibSSHTerminal.DoSendBuffer;
var
  i: Integer;
begin
  LenData := Length(Data);
  FCryptoSSH.PushData(@Data, LenData, i);
  FCryptoSSH.FlushData;
end;

//---------------------------------------------------------------------------

procedure TNsCryptoLibSSHTerminal.DoRecvBuffer;
begin
  LenData := 255;
  FCryptoSSH.PopData(@Data, LenData);
  Self.Lines.Add(Data);
  FCryptoSSH.FlushData;
end;

//---------------------------------------------------------------------------

function TNsCryptoLibSSHTerminal.GetOpened: Boolean;
begin
  Result := FOpened;
end;

//---------------------------------------------------------------------------

function TNsCryptoLibSSHTerminal.GetSession: TNsLibSSH2Session;
begin
  Result := FSession;
end;

//---------------------------------------------------------------------------

function TNsCryptoLibSSHTerminal.GetStatus: string;
begin
  Result := FStatus;
end;

//---------------------------------------------------------------------------

procedure TNsCryptoLibSSHTerminal.SetSession(Value: TNsLibSSH2Session);
begin
  if FSession <> Value then
    FSession := Value;
end;

end.

