unit uFrmMain;

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Actions,
  System.Generics.Collections,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.ActnList,
  Vcl.Samples.Spin,
  uRelayGrabber;

type
  TFrmMain = class(TForm)
    ActionList1: TActionList;
    MemResult: TMemo;
    cmdStart: TAction;
    ProgressBar1: TProgressBar;
    LbLog: TListBox;
    StatusBar: TStatusBar;
    PnTop: TPanel;
    Button1: TButton;
    pnSpin: TPanel;
    seMaxRelays: TSpinEdit;
    Splitter1: TSplitter;
    procedure cmdStartExecute(Sender: TObject);
    procedure LbLogDrawItem(Control: TWinControl; Index: Integer; Rect: TRect;
      State: TOwnerDrawState);
  private
    FScanner: TRelayGrabber;
    function CalculateMaxWidth: Integer;
    procedure UpdateHorizontalScroll;
    procedure OnScannerStarting(Sender: TObject);
    procedure OnScannerProgress(Sender: TObject; Current, Total: Integer;
      const RelayInfo: string);
    procedure OnScannerComplete(Sender: TObject; Results: TObjectList<TTorRelay>);
    procedure OnScannerMessage(Sender: TObject; const Msg: string; Success: Boolean);
  public
    { Public declarations }
  end;

var
  FrmMain: TFrmMain;

implementation

{$R *.dfm}

uses
  Vcl.Themes;

function TFrmMain.CalculateMaxWidth: Integer;
var
  I, TextWidth: Integer;
begin
  Result := 0;

  LbLog.Canvas.Font := LbLog.Font;
  for I := 0 to LbLog.Items.Count - 1 do
  begin
    TextWidth := LbLog.Canvas.TextWidth(LbLog.Items[I]);
    if TextWidth > Result then
      Result := TextWidth;
  end;
  Inc(Result, 16);
end;

procedure TFrmMain.cmdStartExecute(Sender: TObject);
begin
  if FScanner <> nil then
    FScanner.Terminate;
  if cmdStart.Caption = 'Stop' then
    Exit;

  StatusBar.Panels[0].Text := 'Started grab';
  MemResult.Clear;
  LbLog.Clear;
  FScanner := TRelayGrabber.Create('', seMaxRelays.Value);
  FScanner.OnStarting := OnScannerStarting;
  FScanner.OnProgress := OnScannerProgress;
  FScanner.OnComplete := OnScannerComplete;
  FScanner.OnMessage := OnScannerMessage;
  FScanner.Start;
  cmdStart.Caption := 'Stop';
end;

procedure TFrmMain.LbLogDrawItem(Control: TWinControl; Index: Integer;
  Rect: TRect; State: TOwnerDrawState);
var
  b: byte;
  c: TColor;
begin
  if odSelected in State then
  begin
    c := StyleServices.GetSystemColor(clHighlightText);
    LbLog.Canvas.Brush.Color := StyleServices.GetSystemColor(clHighlight);
  end
  else
  begin
    // Иначе рисуем стандартный фон
    LbLog.Canvas.Brush.Color := StyleServices.GetSystemColor(clWindow);
    b := Byte(IntPtr(LbLog.Items.Objects[Index]));
    case b of
      0: c := clRed;
      1: c := clGreen;
      2: c := clBlue;
    end;
  end;
  LbLog.Canvas.FillRect(Rect);
  Inc(Rect.Left, 3);

  LbLog.Canvas.Font.Color := c;
  DrawText(LbLog.Canvas.Handle, PWideChar(LbLog.Items[Index]), -1, Rect,
    DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
end;

procedure TFrmMain.OnScannerStarting(Sender: TObject);
begin
  StatusBar.Panels[0].Text := '';
  ProgressBar1.Visible := true;
end;

procedure TFrmMain.OnScannerComplete(Sender: TObject;
  Results: TObjectList<TTorRelay>);
var
  Relay: TTorRelay;
begin
  for Relay in Results do
  begin
    MemResult.Lines.Add(Format('%s:%d %s',
      [Relay.Address, Relay.ORPort, Relay.Fingerprint]));
  end;
  ProgressBar1.Visible := false;
  StatusBar.Panels[0].Text := 'Ready';
  StatusBar.Panels[1].Text := '';
  FScanner := nil;
  cmdStart.Caption := 'Start';
end;

procedure TFrmMain.OnScannerMessage(Sender: TObject; const Msg: string;
  Success: Boolean);
begin
  LbLog.ItemIndex := LbLog.Items.AddObject(Msg, TObject(IntPtr(Ord(Success))));
  UpdateHorizontalScroll;
end;

procedure TFrmMain.OnScannerProgress(Sender: TObject; Current, Total: Integer;
  const RelayInfo: string);
begin
  ProgressBar1.Max := Total;
  ProgressBar1.Position := Current;
  LbLog.ItemIndex := LbLog.Items.AddObject(RelayInfo, TObject(IntPtr(2)));
  UpdateHorizontalScroll;
  StatusBar.Panels[1].Text := Format('%.0f%%', [100 * Current/Total]);
end;


procedure TFrmMain.UpdateHorizontalScroll;
begin
  SendMessage(LbLog.Handle, LB_SETHORIZONTALEXTENT, CalculateMaxWidth, 0);
end;

end.
