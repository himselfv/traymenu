unit TrayMenu.MainForm;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ExtCtrls, Menus, ImgList, ShlObj;

type
  TFileInfo = record
    Description: string;
    IconIndex: integer;
  end;

  TMainForm = class(TForm)
    TrayIcon: TTrayIcon;
    PopupMenu: TPopupMenu;
    est11: TMenuItem;
    PopupIcons: TImageList;
    DirectoryWatcherTimer: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure TrayIconMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure FormDestroy(Sender: TObject);
    procedure PopupMenuPopup(Sender: TObject);
    procedure DirectoryWatcherTimerTimer(Sender: TObject);

  protected
    FRootPath: string;
    procedure ParseCommandLine;

  protected
    FPopupMenuDirty: boolean;
    procedure ReloadMenu;
    procedure ReloadSubmenu(AParent: TMenuItem; const APath: string);
    procedure SortSubmenu(AParent: TMenuItem);
    function CompareMenuItems(A, B: TMenuItem): integer;

  protected
    procedure TryReadInfo(const AFilename: string; out AInfo: TFileInfo);
    function GetShellLink(const AFilename: string): IShellLink;
    function CopyIcon(const AIcon: HICON): integer;

  protected
    FHDir: THandle;
    FHDirBuf: array[0..1024-1] of byte;
    FHDirOverlapped: TOverlapped;
    procedure SetupDirectoryWatcher;
    procedure CleanupDirectoryWatcher;
    procedure DirectoryWatcherRearm;

  end;

  TDirMenuItem = class(TMenuItem)
  end;

  TLinkMenuItem = class(TMenuItem)
  protected
    FFilename: string;
  public
    constructor Create(AOwner: TComponent; const AFilename: string); reintroduce;
    procedure Click; override;
  end;

var
  MainForm: TMainForm;

implementation
uses SystemUtils, FilenameUtils, CommCtrl, ActiveX, ShellApi;

{$R *.dfm}

procedure TMainForm.FormCreate(Sender: TObject);
begin
  inherited;
  CoInitialize(nil);
  OleInitialize(nil);
  FRootPath := GetSpecialFolderPath(CSIDL_APPDATA)+'\TrayMenu'; //by default
  ParseCommandLine;
  ReloadMenu;
  SetupDirectoryWatcher;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  CleanupDirectoryWatcher;
end;

type
  EBadUsage = class(Exception);

procedure TMainForm.ParseCommandLine;
var i: integer;
  s: string;
begin
  i := 1;
  while i < ParamCount do begin
    s := AnsiLowerCase(Trim(ParamStr(i)));
    if s='' then begin
      Inc(i);
      continue;
    end;

    if s='/path' then begin
      Inc(i);
      if i > ParamCount then
        raise EBadUsage.Create('/path requires specifying path');
      Self.FRootPath := CanonicalizePath(ParamStr(i), GetCurrentDir);
    end;

    raise EBadUsage.Create('Unknown parameter: "'+s+'"');

    Inc(i);
  end;
end;

procedure TMainForm.SetupDirectoryWatcher;
var res: integer;
begin
  FHDir := CreateFile(PChar(Self.FRootPath), FILE_LIST_DIRECTORY, //or GENERIC_READ
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil,
    OPEN_EXISTING, FILE_FLAG_OVERLAPPED or FILE_FLAG_BACKUP_SEMANTICS, 0);
  if FHDir = INVALID_HANDLE_VALUE then FHDir := 0;
  if FHDir = 0 then begin
    res := GetLastError;
    OutputDebugString('Cannot open target path with backup semantics, change notifications will be unavailable');
    OutputDebugString(PChar('GetLastError='+IntToStr(res)));
    exit;
  end;
  DirectoryWatcherRearm;
end;

procedure TMainForm.CleanupDirectoryWatcher;
begin
  if FHDir <> 0 then begin
    CancelIo(FHDir);
    CloseHandle(FHDir);
  end;
end;

//Do not call directly, done automatically
procedure TMainForm.DirectoryWatcherRearm;
var res: integer;
  dwBytes: dword;
begin
  if Self.FHDir = 0 then exit; //can't anything
  FillChar(FHDirOverlapped, SizeOf(FHDirOverlapped), 0);

  //Would be better to assign a completion routine but those don't run without
  //us doing SleepEx or WaitForMessagesEx somewhere

  if not ReadDirectoryChangesW(Self.FHDir, @FHDirBuf[0], SizeOf(FHDirBuf),
    true, //monitor children
    FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_DIR_NAME or
    FILE_NOTIFY_CHANGE_ATTRIBUTES or FILE_NOTIFY_CHANGE_SIZE or
    FILE_NOTIFY_CHANGE_LAST_WRITE or FILE_NOTIFY_CHANGE_CREATION,
    @dwBytes,
    @FHDirOverlapped, nil) then
  begin
    res := GetLastError;
    OutputDebugString('Cannot rearm change notifications, further change notifications will be unavailable');
    OutputDebugString(PChar('GetLastError='+IntToStr(res)));
    //Can't do much on error, won't get any more notifications, sad
  end;
end;

procedure TMainForm.DirectoryWatcherTimerTimer(Sender: TObject);
var dwBytes: dword;
begin
  if Self.FHDir = 0 then exit;
  if GetOverlappedResult(Self.FHDir, Self.FHDirOverlapped, dwBytes, false) then begin
    FPopupMenuDirty := true;
    DirectoryWatcherRearm;
  end;
end;


procedure TMainForm.PopupMenuPopup(Sender: TObject);
begin
  if FPopupMenuDirty then
    ReloadMenu;
end;

procedure TMainForm.ReloadMenu;
begin
  FPopupMenuDirty := false;
  PopupIcons.Clear;
  ReloadSubmenu(PopupMenu.Items, FRootPath);
end;

procedure TMainForm.ReloadSubmenu(AParent: TMenuItem; const APath: string);
var sr: TSearchRec;
  res: integer;
  item: TMenuItem;
  info: TFileInfo;
begin
  AParent.Clear;
  if APath = '' then exit;

  res := SysUtils.FindFirst(APath+'\*.*', faAnyFile, sr);
  while res = 0 do begin
    if (sr.Name='') or (sr.Name='.') or (sr.Name='..') then begin
      res := SysUtils.FindNext(sr);
      continue;
    end;
    if (sr.Name[1]='.') or (sr.Attr and faHidden <> 0) then begin
      res := SysUtils.FindNext(sr);
      continue;
    end;

    if sr.Attr and faDirectory <> 0 then begin
      item := TDirMenuItem.Create(Self.PopupMenu);
      item.Caption := sr.Name;
      TryReadInfo(APath+'\'+sr.Name, info);
      item.ImageIndex := info.IconIndex;
      AParent.Add(item);
      ReloadSubmenu(item, APath+'\'+sr.Name);
    end else begin
      item := TLinkMenuItem.Create(Self.PopupMenu, APath+'\'+sr.Name);
      item.Caption := ChangeFileExt(sr.Name, '');
      TryReadInfo(APath+'\'+sr.Name, info);
      item.Hint := info.Description;
      item.ImageIndex := info.IconIndex;
      AParent.Add(item);
    end;
    res := SysUtils.FindNext(sr);
  end;
  SysUtils.FindClose(sr);

  SortSubmenu(AParent);
end;

procedure TMainForm.SortSubmenu(AParent: TMenuItem);
var i, j: integer;
  item: TMenuItem;
begin
  i := 0;
  while i < AParent.Count-1 do begin
    j := i-1;
    while j >= 0 do begin
      if CompareMenuItems(AParent.Items[j], AParent.Items[i]) <= 0 then begin
        if j<i-1 then begin
          item := AParent.Items[i];
          AParent.Remove(item);
          AParent.Insert(j+1, item);
        end;
        break;
      end;
      Dec(j);
    end;
    if j < 0 then begin
      item := AParent.Items[i];
      AParent.Remove(item);
      AParent.Insert(0, item);
    end;
    Inc(i);
  end;
end;

function TMainForm.CompareMenuItems(A, B: TMenuItem): integer;
var AD, BD: boolean;
begin
  AD := (A is TDirMenuItem);
  BD := (B is TDirMenuItem);
  if AD <> BD then begin
    if AD then
      Result := -1
    else
      Result := +1;
    exit;
  end;
  Result := CompareText(A.Caption, B.Caption);
end;

procedure TMainForm.TryReadInfo(const AFilename: string; out AInfo: TFileInfo);
var psl: IShellLink;
  shInfo: SHFILEINFO;
  res: integer;
begin
  AInfo.Description := '';
  AInfo.IconIndex := -1;

  //If this is a link, we can query its link description
  psl := Self.GetShellLink(AFilename);
  if psl <> nil then begin
    SetLength(AInfo.Description, MAX_PATH+1);
    if SUCCEEDED(psl.GetDescription(PChar(AInfo.Description), MAX_PATH)) then
      SetLength(AInfo.Description, StrLen(PChar(AInfo.Description))) //trim
    else
      AInfo.Description := '';
  end;

  //For files and folders we can query their explorer icons + type descriptions
  res := ShellApi.SHGetFileInfo(PChar(AFilename), 0, shInfo, SizeOf(shInfo), SHGFI_TYPENAME or SHGFI_SMALLICON or SHGFI_SYSICONINDEX);
  if res <> 0 then begin
    if AInfo.Description='' then
      AInfo.Description := shInfo.szTypeName;
    //Icon from hIcon has [link] overlay, we prefer to get the system index and query directly
    if shInfo.hIcon <> 0 then
      DestroyIcon(shInfo.hIcon);
    if (AInfo.IconIndex < 0) and (shInfo.iIcon <> 0) then begin
      shInfo.hIcon := ImageList_GetIcon(res, shInfo.iIcon, ILD_NORMAL);
      if shInfo.hIcon = 0 then
        shInfo.hIcon := GetLastError;
      AInfo.IconIndex := Self.CopyIcon(shInfo.hIcon);
      DestroyIcon(shInfo.hIcon);
    end;
  end;
end;

function TMainForm.GetShellLink(const AFilename: string): IShellLink;
var ppf: IPersistFile;
begin
  Result := nil;
  if FAILED(CoCreateInstance(CLSID_ShellLink, nil, CLSCTX_INPROC_SERVER, IID_IShellLink, Result)) then
    exit;
  if FAILED(Result.QueryInterface(IPersistFile, ppf))
  or FAILED(ppf.Load(PChar(AFilename), STGM_READ)) then begin
    Result := nil;
    exit;
  end;
end;

function TMainForm.CopyIcon(const AIcon: HICON): integer;
var icon: TIcon;
begin
  icon := TIcon.Create;
  icon.Handle := AIcon;
  Result := PopupIcons.AddIcon(icon);
end;

procedure TMainForm.TrayIconMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then begin
    SetForegroundWindow(Application.Handle);
    Application.ProcessMessages;
    PopupMenu.AutoPopup := False;
    PopupMenu.PopupComponent := TrayIcon;
    PopupMenu.Popup(X, Y);
  end;
end;

constructor TLinkMenuItem.Create(AOwner: TComponent; const AFilename: string);
begin
  inherited Create(AOwner);
  Self.FFilename := AFilename;
end;

procedure TLinkMenuItem.Click;
begin
  inherited;
  ShellExecute(0, PChar('open'), PChar(Self.FFilename), nil, nil, SW_SHOW);
end;


end.
