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
  protected
    FRootPath: string;
    procedure ParseCommandLine;
    procedure ReloadMenu;
    procedure ReloadSubmenu(AParent: TMenuItem; const APath: string);

  protected
    procedure TryReadInfo(const AFilename: string; out AInfo: TFileInfo);
    function GetShellLink(const AFilename: string): IShellLink;
    function CopyIcon(const AIcon: HICON): integer;

  end;

var
  MainForm: TMainForm;

implementation
uses FilenameUtils, ActiveX, ShellApi;

{$R *.dfm}

procedure TMainForm.FormCreate(Sender: TObject);
begin
  inherited;
  CoInitialize(nil);
  OleInitialize(nil);
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
    end else

    raise EBadUsage.Create('Unknown parameter: "'+s+'"');

    Inc(i);
  end;
end;

procedure TMainForm.ReloadMenu;
begin
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
    if (sr.Name='.') or (sr.Name='..') then begin
      res := SysUtils.FindNext(sr);
      continue;
    end;

    item := TMenuItem.Create(Self.PopupMenu);
    AParent.Add(item);

    if sr.Attr and faDirectory <> 0 then begin
      ReloadSubmenu(item, APath+'\'+sr.Name);
    end else begin
      item.Caption := ChangeFileExt(sr.Name, '');
      TryReadInfo(APath+'\'+sr.Name, info);
      item.Hint := info.Description;
      item.ImageIndex := info.IconIndex;
    end;
    res := SysUtils.FindNext(sr);
  end;
  SysUtils.FindClose(sr);
end;

procedure TMainForm.TryReadInfo(const AFilename: string; out AInfo: TFileInfo);
var psl: IShellLink;
  shInfo: SHFILEINFO;
  res: integer;
begin
  AInfo.Description := '';
  AInfo.IconIndex := -1;

  psl := Self.GetShellLink(AFilename);
  if psl <> nil then begin
    SetLength(AInfo.Description, MAX_PATH+1);
    if SUCCEEDED(psl.GetDescription(PChar(AInfo.Description), MAX_PATH)) then
      SetLength(AInfo.Description, StrLen(PChar(AInfo.Description))) //trim
    else
      AInfo.Description := '';
  end;

  res := SHGetFileInfo(PChar(AFilename), 0, shInfo, SizeOf(shInfo), SHGFI_TYPENAME or SHGFI_ICON or SHGFI_SMALLICON);
  if res <> 0 then begin
    if AInfo.Description='' then
      AInfo.Description := shInfo.szTypeName;
    if shInfo.hIcon <> 0 then begin
      if AInfo.IconIndex < 0 then
        AInfo.IconIndex := Self.CopyIcon(shInfo.hIcon);
      DestroyIcon(shInfo.hIcon);
    end;
  end else
    AInfo.IconIndex := res;
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


end.
