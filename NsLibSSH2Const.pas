unit NsLibSSH2Const;

{
  version 1.0
}

interface

uses
  Windows, libssh2_sftp, SysUtils;

const
  AUTH_NONE = 0;
  AUTH_PASSWORD = 1;
  AUTH_PUBLICKEY = 2;

// Default values
  VAL_EMPTY_STR = '';
  VAL_ZERO = 0;
  VAL_FALSE = False;
  DEFAULT_SSH_PORT = 22;
  DEFAULT_LOCAL_HOST = '127.0.0.1';
  DEFAULT_REMOTE_HOST = '192.168.1.1';
  DEFAULT_LOCAL_PORT = 3389;
  DEFAULT_REMOTE_PORT = 3389;

// Statuses
  ST_CONNECTED = 'Connected';
  ST_DISCONNECTED = 'Disconnected';
  ST_SESSION_CLOSED = 'Session closed normally';

// Error messages
  ER_WSAERROR = 'WSAStartup failed with error: %d';
  ER_LIBSSH2_INIT = 'libssh2 initialization failed with error: %d';
  ER_OPEN_SOCKET = 'Failed to open socket';
  ER_IP_INCORRECT = 'IP address is incorrect';
  ER_CONNECT = 'Failed to connect to server';
  ER_SESSION_INIT = 'Could not initialize SSH session';
  ER_SESSION_START = 'Error when starting up SSH session: %d';
  ER_AUTH_METHOD = 'No supported authentication methods found';
  ER_PUBKEY = 'Authentication by public key failed';
  ER_PASSWORD = 'Authentication by password failed';
  ER_SESSION_UNAVAILABLE = 'Session is not available';
  ER_BINDING = 'Cannot bind socket with IP address: %d';
  ER_SOCKET_LISTEN = 'Socket cannot listen';
  ER_FTP_OPEN = 'Unable to open SFTP session';
  ER_FTP_OPENFILE = 'Unable to open file with SFTP: %d';
  ER_DEST_NOT_EXISTS = 'Destination folder not exists';
  ER_CHANNEL_OPEN = 'Unable to open a channel';
  ER_FAILED_PTY = 'Failed requesting pty';
  ER_REQUEST_SHELL = 'Unable to request shell on allocated pty';

procedure DebugLog(S: String); overload;
procedure DebugLog(I: Integer); overload;

var
  FileBusy: Boolean;

implementation

procedure CheckLogExists;
var
  F: TextFile;
begin
  if not FileExists('debug.log') then
    begin
      AssignFile(F, 'debug.log');
      Rewrite(F);
      Writeln(F, '==== DEBUG LOG ====');
      CloseFile(F);
    end;
end;

procedure DebugLog(S: String);
var
  F: TextFile;
begin

  while True do
    if not FileBusy then
      begin
        try
          FileBusy := True;
          CheckLogExists;
          AssignFile(F, 'debug.log');
          Append(F);
          WriteLn(F, S);
          CloseFile(F);
          FileBusy := False;
          Break;
        except
          ;
        end;
      end;
end;

procedure DebugLog(I: Integer);
var
  F: TextFile;
begin
  CheckLogExists;

  try
    AssignFile(F, 'debug.log');
    Append(F);
    WriteLn(F, IntToStr(I));
    CloseFile(F);
  except
    ;
  end;
end;

end.

