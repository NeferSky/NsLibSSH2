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
  DEFAULT_EMPTY_STR = '';
  DEFAULT_SSH_PORT = 22;
  DEFAULT_LOCAL_HOST = '127.0.0.1';
  DEFAULT_REMOTE_HOST = '192.168.1.1';
  DEFAULT_LOCAL_PORT = 3389;
  DEFAULT_REMOTE_PORT = 3389;

  // Max counts
  MAX_CONNECTION_ATTEMPTS = 10;
  MAX_POOL_SIZE = 4;
  FTP_PACKET_SIZE = 102400;

  // Statuses
  ST_CONNECTED = 'Connected';
  ST_DISCONNECTED = 'Disconnected';
  ST_SESSION_CLOSED = 'Session closed normally';

  // Results
  INVALID_POOL_ITEM_INDEX = -1;

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

implementation

end.

