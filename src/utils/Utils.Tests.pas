/// <summary> Unit which has classes to parse the xml file containing tests report 
/// generated by the test application. Should be a file generated by fpcunit using
/// xml format option.
/// </summary>
unit Utils.Tests;

{$MODE DELPHI}{$H+}

interface

uses
  Classes,
  SysUtils,
  DOM, 
  XmlRead,
  Command.Interfaces;

type

  /// <summary> Class that represents a single test case report data.
  /// </summary>
  TTestCaseItem = class
  private
    FStatus: string;
    FTime: string;
    FTestSuite: string;
    FTestCase: string;
    FError: string;
  public
    /// <summary> Returns an instance of the class with the test suite name and test case name filled.
    /// </summary>
    class function New(const ATestSuite, ATestCase: string): TTestCaseItem;

    /// <summary> Status execution of the test case. Can be OK or Failed. </summary>
    property Status: string read FStatus write FStatus;

    /// <summary> Time the test took to run </summary>
    property Time: string read FTime write FTime;

    /// <summary> Test suite name </summary>
    property TestSuite: string read FTestSuite write FTestSuite;

    /// <summary> Test case name </summary>
    property TestCase: string read FTestCase write FTestCase;

    /// <summary> Error message detailing the test case that failed </summary>
    property Error: string read FError write FError;
  end;

  /// <sumary> This class aims to interpret the fpcunit test xml file and produce 
  /// a simpler report summarizing all tests cases and also providing their location
  /// on source code.
  /// </summary>
  TTestReport = class
  private
    FBuilder: ICommandBuilder;
    FExecutable: string;
    FProjectSource: string;
    FTestCaseCount: Integer;
    FTestSuiteCount: Integer;
    FTotalTime: string;
    FTestsPassed: Integer;
    FTestsFailed: Integer;
    FTestCaseData: TArray<TTestCaseItem>;

    /// <summary> Search for the text in the string list and returns the line number 
    /// where it was found. The result is formatted like this "1:1" (line:column).
    /// <param name="ACodeFile"> TStringList object with content already loaded </param>
    /// <param name="AText"> Text to be searched </param>
    function FindInCodeFile(ACodeFile: TStringList; const AText: string): string;

    /// <summary> Considering the name of the test suite, recursively, starting from 
    /// the given path, it looks for a source code file that contains a class with 
    /// the name of the suite. </summary>
    /// <param name="ACurrentDir"> Path to start the search </param>
    /// <param name="ATestSuite"> Test suite name to be searched </param>
    /// <param name="AFoundOutput"> Returns the filename with relative path from ACurrentDir. 
    /// It is concatenated to the filename ":Line:Column" which indicates the location of 
    /// the code found. </param>
    procedure GetCodeFileForTestSuite(const ACurrentDir, ATestSuite: string; out AFoundOutput: string);

    /// <summary> Returns a string representing the value of a node or attribute from 
    /// an xml document. </summary>
    function GetString(ANode: TDOMNode; const AAttribute: string): string;

    /// <summary> Eliminates non-significant hours or minutes from a time string. 
    /// Ex: '00:1.210' returns '1:210' </summary>
    /// <param name="ATime"> String time in format hh:mm:ss.zzz </param>
    function TrimTime(const ATime: string): string;

  public

    /// <summary> Class constructor that initializes array that hold test case data. 
    /// Check factory method new as the best option.
    /// </summary>
    constructor Create;

    /// <summary> The class's destructor frees all TTestCaseItem instances created during parse.
    /// </summary>
    destructor Destroy; override;

    /// <summary> It is the best way to create a new instance of the class,
    /// as it considers its dependencies. </summary>
    /// <param Name="ABuilder"> A valid instance of ICommandBuilder. Basically it will be 
    /// used to generate the output to the console considering the theme settings.</param>
    /// <param Name="AProjectSource"> The path to the source code, needed to find the files
    /// corresponding to the source code reported in the fpcunit xml test file. </param>
    class function New(ABuider: ICommandBuilder; const AProjectSource: string): TTestReport;

    /// <summary> Parses the contents of the test xml file generated by the fpunit tests 
    /// frameworkk. Groups the information into a TTestCaseItem list. It summarizes the total 
    /// of tests, tests that passed, tests that failed in addition to searching for the 
    /// location of the tests that failed in the source code. </summary> 
    /// <param name="ATestApp"> Test application name that will be printed along with 
    /// the test report output </param>
    /// <param name="AFileName"> Unit test xml file generated by the test application </param>
    function ParseXmlTestsFile(const ATestApp, AFileName: string): TTestReport;

    /// <summary> Adds a new TestCaseItem to TestCaseData, internally used by ParseXmlTestsFile.
    /// </summary>
    /// <param name="AItem"> The item to be added to TestCaseData </param>
    function AddItem(AItem: TTestCaseItem): TTestCaseItem;

    /// <summary> Generates a colorful and well-aligned report listing all successful and 
    /// unsuccessful test cases. For failed test cases, it presents detailed information 
    /// and the location of the test routine in its respective source code file. </summary>
    procedure Output;

    /// <summary> Test project excutable name. </summary> 
    property Executable: string read FExecutable write FExecutable;

    /// <summary> Path to test project source files </summary> 
    property ProjectSource: string read FProjectSource write FProjectSource;

    /// <summary> Total test cases found on xml test file after parse </summary> 
    property TestCaseCount: Integer read FTestCaseCount write FTestCaseCount;

    /// <summary> Total test suites found on xml test file after parse </summary> 
    property TestSuiteCount: Integer read FTestSuiteCount write FTestSuiteCount;

    /// <summary> Total test elapsed time found on xml test file after parse </summary> 
    property TotalTime: string read FTotalTime write FTotalTime;

    /// <summary> Total test that passed found on xml test file after parse </summary> 
    property TestsPassed: Integer read FTestsPassed write FTestsPassed;

    /// <summary> Total test that passed found on xml test file after parse </summary> 
    property TestsFailed: Integer read FTestsFailed write FTestsFailed;

    /// <summary> All test case found on xml test file after parse </summary> 
    property TestCaseData: TArray<TTestCaseItem> read FTestCaseData write FTestCaseData;
  end;

implementation

uses
  StrUtils,
  Math,
  Command.Colors;

constructor TTestReport.Create;
begin
  SetLength(FTestCaseData, 0);
end;

destructor TTestReport.Destroy;
var
  LItem: TTestCaseItem;
begin
  for LItem in FTestCaseData do
    LItem.Free;
  SetLength(FTestCaseData, 0);
  inherited Destroy;
end;

class function TTestReport.New(ABuider: ICommandBuilder; const AProjectSource: string): TTestReport;
begin
  Result := Self.Create;
  Result.ProjectSource := AProjectSource;
  Result.FBuilder := ABuider;
end;

procedure TTestReport.GetCodeFileForTestSuite(const ACurrentDir, ATestSuite: string; out AFoundOutput: string);
var
  LContent: TStringList = nil;
  LSearch: TSearchRec;
  LCurrentDir, LExt, LCodeFile: string;
begin
  if not DirectoryExists(ACurrentDir) then
    Exit;
  
  if FindFirst(ConcatPaths([ACurrentDir, AllFilesMask]), faAnyFile or faDirectory, LSearch) = 0 then
    try
      repeat
        if ((LSearch.Attr and faDirectory) <> 0) and (not AnsiMatchText(LSearch.Name, ['.', '..'])) then
        begin
          LCurrentDir := ConcatPaths([ACurrentDir, LSearch.Name]);
          GetCodeFileForTestSuite(LCurrentDir, ATestSuite, AFoundOutput);
          if AFoundOutput <> '' then
            Exit;
        end 
        else
        begin
          LExt := ExtractFileExt(LSearch.Name);
          if ((LSearch.Attr and faAnyFile) <> 0) and AnsiMatchText(LExt, ['.pp', '.pas', '.lpr']) then
          begin
            AFoundOutput := '';
            LCodeFile := ConcatPaths([ACurrentDir, LSearch.Name]);

            LContent := TStringList.Create;
            try
              LContent.LoadFromFile(LCodeFile);
              AFoundOutput := FindInCodeFile(LContent, ATestSuite);
            finally
              LContent.Free;
            end;

            if AFoundOutput <> '' then
            begin
              AFoundOutput := LCodeFile + ':' + AFoundOutput;
              FindClose(LSearch);
              Exit;
            end;
          end;
        end; 
      until FindNext(LSearch) <> 0;
    finally
      FindClose(LSearch);
    end;  
end;

function TTestReport.FindInCodeFile(ACodeFile: TStringList; const AText: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to ACodeFile.Count - 1 do
    if ContainsText(ACodeFile.Strings[I], AText) then
      Exit(IntToStr(I + 1) + ':1');
end;

function TTestReport.ParseXmlTestsFile(const ATestApp, AFileName: string): TTestReport;
var
  LXml: TXMLDocument;
  LTestSuiteList: TDOMNodeList;
  LTestSuite, LTestCase: TDOMNode;
  I, J, K: Integer;
  LItem: TTestCaseItem;
  LSourceInfo: string;
begin
  Result := Self;
  try
    if not FileExists(AFileName) then
    begin
      FBuilder.OutputColor(
        'Arquivo: ' + AFileName + ' não encontrado.'#13#10, 
        FBuilder.ColorTheme.Text);
      Exit;
    end;

    ReadXMLFile(LXml, AFileName);
    
    LTestSuiteList := LXml.DocumentElement.GetElementsByTagName('TestSuite');
    Executable := ATestApp;
    TestSuiteCount := LTestSuiteList.Count;
    TestCaseCount := 0;
    TestsPassed := 0;
    TestsFailed := 0;
    for I := 0 to LTestSuiteList.Count -1 do
    begin
      LTestSuite := LTestSuiteList[I];

      if I = 0 then
        TotalTime := GetString(LTestSuite, 'ElapsedTime');

      if (GetString(LTestSuite, 'Name') = '') or (SameText(GetString(LTestSuite, 'Name'), 'SuiteList')) then
        continue;

      if (LTestSuite.HasAttributes) and (SameText(String(LTestSuite.Attributes[0].NodeName), 'name')) then
      begin
        // determina qual é a unit que possui essa suite de testes
        for j := 0 to LTestSuite.ChildNodes.Count - 1 do
        begin
          LTestCase := LTestSuite.ChildNodes[J];

          Inc(FTestCaseCount);
          LItem := TTestCaseItem.New(GetString(LTestSuite, 'Name'), GetString(LTestCase, 'Name'));
          AddItem(LItem);

          LItem.Status := GetString(LTestCase, 'Result');
          LItem.Time := GetString(LTestCase, 'ElapsedTime');

          if SameText('OK', LItem.Status) then
          begin
            Inc(FTestsPassed)
          end
          else
          begin
            Inc(FTestsFailed);
            
            LItem.Error := '';
            
            GetCodeFileForTestSuite(ProjectSource, LItem.TestSuite + '.' + LItem.TestCase, LSourceInfo);
            LItem.Error := LSourceInfo;
            
            for K := 0 to LTestCase.ChildNodes.Count - 1 do
              LItem.Error := LItem.Error + 
                IfThen(LItem.Error = '', '', #13#10) + 
                String(LTestCase.ChildNodes[K].TextContent);
          end;
        end;
      end;
    end;
  finally
    LXml.Free;
  end;
end;

function TTestReport.AddItem(AItem: TTestCaseItem): TTestCaseItem;
begin
  SetLength(FTestCaseData, Length(FTestCaseData) + 1);
  FTestCaseData[Length(FTestCaseData) - 1] := AItem;
  Result := AItem;
end;

function TTestReport.GetString(ANode: TDOMNode; const AAttribute: string): string;
var
  LAttr: TDOMNode;
begin
  Result := '';
  LAttr := ANode.Attributes.GetNamedItem(UnicodeString(AAttribute));
  if Assigned(LAttr) then
    Result := String(LAttr.NodeValue);
end;

function TTestReport.TrimTime(const ATime: string): string;
begin
  Result := ATime;
  if StartsText('00:', Result) then
    Result := TrimTime(Copy(Result, 4));
end;

procedure TTestReport.Output;
var
  LItem: TTestCaseItem;
  LColor: byte;
begin
  FBuilder.OutputColor(PadLeft('Executable ', 13), FBuilder.ColorTheme.Value);
  FBuilder.OutputColor(Executable + #13#10, FBuilder.ColorTheme.Text);

  FBuilder.OutputColor(PadLeft('Starting ', 13), FBuilder.ColorTheme.Value);
  FBuilder.OutputColor(
    IntToStr(TestCaseCount) + ' test cases across ' +
    IntToStr(TestSuiteCount) + ' test suites'#13#10, 
    FBuilder.ColorTheme.Other);
  
  for LItem in TestCaseData do
  begin
    LColor := IfThen(LItem.Status <> 'OK', FBuilder.ColorTheme.Error, LightGreen);

    FBuilder.OutputColor(PadLeft(LItem.Status + ' ', 13), LColor);
    FBuilder.OutputColor('[' + PadLeft(TrimTime(LItem.Time), 12) + ']', FBuilder.ColorTheme.Other);
    FBuilder.OutputColor(
      ' ' + LItem.TestSuite + '.' + LItem.TestCase + #13#10, 
      FBuilder.ColorTheme.Other);

    if LItem.Status <> 'OK' then
    begin
      FBuilder.Output('');
      FBuilder.OutputColor(LItem.Error, FBuilder.ColorTheme.Other);
      FBuilder.Output('');
      FBuilder.Output('');
    end;
  end;

  FBuilder.OutputColor(PadLeft('Summary ', 13), FBuilder.ColorTheme.Value);
  FBuilder.OutputColor('[' + PadLeft(TrimTime(TotalTime), 12) + ']', FBuilder.ColorTheme.Other);
  FBuilder.OutputColor(' ' +
    IntToStr(TestCaseCount) + ' tests cases run: ' +
    IntToStr(TestsPassed) + ' passed, ' +
    IntToStr(TestsFailed) + ' failed.',
    FBuilder.ColorTheme.Other);
  FBuilder.Output('');
end;

class function TTestCaseItem.New(const ATestSuite: string; const ATestCase: string): TTestCaseItem;
begin
  Result := Self.Create;
  Result.TestSuite := ATestSuite;
  Result.TestCase := ATestCase;
end;

end.
