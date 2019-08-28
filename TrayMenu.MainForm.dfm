object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'MainForm'
  ClientHeight = 81
  ClientWidth = 199
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 13
  object TrayIcon: TTrayIcon
    PopupMenu = PopupMenu
    Visible = True
    Left = 16
    Top = 16
  end
  object PopupMenu: TPopupMenu
    Images = PopupIcons
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
end
