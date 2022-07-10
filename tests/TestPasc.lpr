program TestPasc;

{$mode objfpc}{$H+}

uses
  Classes, 
  SysUtils,
  consoletestrunner, 
  Resources,
  TestUtilsIO,
  TestUtilsLeak,
  TestUtilsResources,
  TestUtilsShell,
  TestUtilsTests,
  TestCommandClean,
  TestCommandInstall,
  TestCommandNew,
  TestCommandTest, MockCommandBuilder;

type

  { TTestPascRunner }

  TTestPascRunner = class(TTestRunner)
  protected
  // override the protected methods of TTestRunner to customize its behavior
  end;

{$R *.res}

var
  Application: TTestPascRunner;

begin
  {$IF DECLARED(UseHeapTrace)}
  if FileExists('tests/heap.trc') then
    DeleteFile('tests/heap.trc');
  SetHeapTraceOutput('tests/heap.trc');
  {$ENDIF}
  Application := TTestPascRunner.Create(nil);
  Application.Initialize;
  Application.Title := 'pasc console test runner';
  Application.Run;
  Application.Free;
end.
