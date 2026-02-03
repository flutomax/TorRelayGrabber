program TorRelayGrabber;

uses
  Vcl.Forms,
  uFrmMain in 'uFrmMain.pas' {FrmMain},
  uRelayGrabber in 'uRelayGrabber.pas',
  Vcl.Themes,
  Vcl.Styles;

{$R *.res}

begin
  Randomize;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  TStyleManager.TrySetStyle('Glossy');
  Application.CreateForm(TFrmMain, FrmMain);
  Application.Run;
end.
