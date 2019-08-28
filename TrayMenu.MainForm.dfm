object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'MainForm'
  ClientHeight = 81
  ClientWidth = 249
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 13
  object TrayIcon: TTrayIcon
    PopupMenu = PopupMenu
    Visible = True
    OnMouseUp = TrayIconMouseUp
    Left = 16
    Top = 16
  end
  object PopupMenu: TPopupMenu
    Images = PopupIcons
    OnPopup = PopupMenuPopup
    Left = 72
    Top = 16
    object est11: TMenuItem
      Caption = 'Test1'
    end
  end
  object PopupIcons: TImageList
    ColorDepth = cd32Bit
    DrawingStyle = dsTransparent
    Left = 136
    Top = 16
  end
  object DirectoryWatcherTimer: TTimer
    Interval = 500
    OnTimer = DirectoryWatcherTimerTimer
    Left = 200
    Top = 16
  end
end
