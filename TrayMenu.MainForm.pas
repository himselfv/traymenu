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
    procedure FormCreate(Sender: TObject);
    procedure TrayIconMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  protected
    FRootPath: string;
    procedure ParseCommandLine;
    procedure ReloadMenu;
    procedure ReloadSubmenu(AParent: TMenuItem; const APath: string);
    procedure SortSubmenu(AParent: TMenuItem);
    function CompareMenuItems(A, B: TMenuItem): integer;
    procedure MenuReloadClick(Sender: TObject);

  protected
    procedure TryReadInfo(const AFilename: string; out AInfo: TFileInfo);
    function GetShellLink(const AFilename: string): IShellLink;
    function CopyIcon(const AIcon: HICON): integer;

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
uses FilenameUtils, CommCtrl, ActiveX, ShellApi;

{$R *.dfm}

procedure TMainForm.FormCreate(Sender: TObject);
begin
  inherited;
  CoInitialize(nil);
  OleInitialize(nil);
  FRootPath := GetSpecialFolderPath(CSIDL_APPDATA)+'\TrayMenu'; //by default
  ParseCommandLine;
  ReloadMenu;
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

procedure TMainForm.ReloadMenu;
var item: TMenuItem;
begin
  PopupIcons.Clear;
  ReloadSubmenu(PopupMenu.Items, FRootPath);

  item := TMenuItem.Create(PopupMenu);
  item.Caption := '-';
  PopupMenu.Items.Add(item);

  item := TMenuItem.Create(PopupMenu);
  item.Caption := 'Reload';
  item.OnClick := MenuReloadClick;
  PopupMenu.Items.Add(item);
end;

procedure TMainForm.MenuReloadClick(Sender: TObject);
begin
  ReloadMenu;
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
