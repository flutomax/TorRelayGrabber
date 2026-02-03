object FrmMain: TFrmMain
  Left = 0
  Top = 0
  Caption = 'Tor Relay Grabber'
  ClientHeight = 441
  ClientWidth = 624
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  TextHeight = 15
  object Splitter1: TSplitter
    Left = 0
    Top = 307
    Width = 624
    Height = 3
    Cursor = crVSplit
    Align = alBottom
    ExplicitTop = 33
    ExplicitWidth = 277
  end
  object MemResult: TMemo
    Left = 0
    Top = 310
    Width = 624
    Height = 112
    Align = alBottom
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 0
  end
  object LbLog: TListBox
    Left = 0
    Top = 33
    Width = 624
    Height = 274
    Style = lbOwnerDrawFixed
    Align = alClient
    TabOrder = 2
    OnDrawItem = LbLogDrawItem
  end
  object StatusBar: TStatusBar
    Left = 0
    Top = 422
    Width = 624
    Height = 19
    Panels = <
      item
        Text = 'Ready'
        Width = 200
      end
      item
        Width = 100
      end>
    object ProgressBar1: TProgressBar
      Left = 1
      Top = 3
      Width = 198
      Height = 14
      TabOrder = 0
      Visible = False
    end
  end
  object PnTop: TPanel
    Left = 0
    Top = 0
    Width = 624
    Height = 33
    Align = alTop
    BevelOuter = bvNone
    BorderWidth = 4
    TabOrder = 3
    object Button1: TButton
      Left = 4
      Top = 4
      Width = 75
      Height = 25
      Action = cmdStart
      Align = alLeft
      TabOrder = 0
    end
    object pnSpin: TPanel
      Left = 483
      Top = 4
      Width = 137
      Height = 25
      Align = alRight
      Alignment = taLeftJustify
      BevelOuter = bvNone
      BorderWidth = 1
      Caption = 'Max Relays:'
      TabOrder = 1
      object seMaxRelays: TSpinEdit
        Left = 71
        Top = 1
        Width = 65
        Height = 24
        Align = alRight
        MaxValue = 0
        MinValue = 0
        TabOrder = 0
        Value = 100
      end
    end
  end
  object ActionList1: TActionList
    Left = 296
    Top = 104
    object cmdStart: TAction
      Caption = 'Start'
      OnExecute = cmdStartExecute
    end
  end
end
