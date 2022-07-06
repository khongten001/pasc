/// <summary> Unit which has classes to process the trace file containing memory leak 
/// data generated by the application. 
/// </summary>
unit Utils.Leak;

{$MODE DELPHI}{$H+}

interface

uses
  Classes,
  SysUtils,
  Command.Interfaces;

type
  /// <summary> Class that represents a single point in code with the possible memory leak.
  /// </summary>
  TLeakItem = class
  private
    FStatus: string;
    FSize: string;
    FSource: string;
  public
    /// <summary> Returns an instance of the class with the status and memory leak size filled.
    /// </summary>
    class function New(const AStatus, ASize: string): TLeakItem;

    /// <summary> Item status. Currently it can only be Leak.</summary>
    property Status: string read FStatus write FStatus;

    /// <summary> Memory leak size in bytes </summary>
    property Size: string read FSize write FSize;

    /// <summary> Data about the source code where the leak originated, 
    /// as well as the method and code line number within the file. </summary>
    property Source: string read FSource write FSource;
  end;

  /// <sumary> This class aims to interpret the memory leak trace file and produce 
  /// a simpler report summarizing enough information to locate the problem at its source.
  /// </summary>
  TLeakReport = class
  private
    FBuilder: ICommandBuilder;

    FExecutable: string;
    FProjectSource: string;
    FHeapDataIsMissing: Boolean;
    FTotalLeakSize: Integer;
    FTotalLeakInfo: string;
    FLeakData: TArray<TLeakItem>;
   
  public
    /// <summary> Class constructor that initializes arrays and control variables. 
    /// Check factory method new as the best option.
    /// </summary>
    constructor Create;

    /// <summary> The class's destructor frees all TLeakItem instances created during parse.
    /// </summary>
    destructor Destroy; override;

    /// <summary> It is the best way to create a new instance of the class,
    /// as it considers its dependencies. </summary>
    /// <param Name="ABuilder"> A valid instance of ICommandBuilder. Basically it will be 
    /// used to generate the output to the console considering the theme settings.</param>
    /// <param Name="AProjectSource"> The path to the source code, needed to find the files
    /// corresponding to the source code reported in the memory leak trace file. </param>
    class function New(ABuider: ICommandBuilder; const AProjectSource: string): TLeakReport;

    /// <summary> Adds a new memory leak item to the report.</summary>
    function AddItem(AItem: TLeakItem): TLeakItem;

    /// <summary> Scans the contents of the AContent variable to summarize the details 
    /// of a memory leak reported in the trace file. If a memory leak is found then it
    /// added to the report calling AddItem method. </summary>
    procedure CreateLeakItem(AContent: TStringList; AStart: Integer);

    /// <summary> Considering the content of AText, it searches for the string AField, 
    /// if successful, returns the value immediately to the right of that string. 
    /// The returned value will be limited until it finds the next space or the end 
    /// of the string. </summary>
    function GetNextStringOf(const AText, AField: string): string;

    /// <summary> Given a filename, try to locate it recursively in the projects folder, 
    /// then in the current directory. If the file is found, the relative path will be 
    /// added to the file name. </summary>
    function AddRelativePath(const AFile: string): string;

    /// <summary> Prints a report using ICommandBuilder's Output Callback. This report will have 
    /// data regarding possible memory leaks like size, source method and source code 
    /// file with line number. If no leak was found, it will display a message indicating 
    /// the same. </summary>
    procedure Output;

    /// <summary> Parses the contents of the trace file generated by the HeapTrace unit. 
    /// Groups the information into a TLeakItem list. </summary> 
    /// <param name="AContent"> Accepts the contents of the memory leak trace file. 
    /// If an empty string is passed, the method will try to locate the heap.trc file 
    /// in the test project's executable directory. </param>
    function ParseHeapTrace(const AContent: string): TLeakReport;    

    /// <summary> Test project excutable name. </summary> 
    property Executable: string read FExecutable write FExecutable;

    /// <summary> Path to test project source files </summary> 
    property ProjectSource: string read FProjectSource write FProjectSource;

    /// <summary> Array of TLeakItem that is generated after calling ParseHeapTrace method.
    /// </summary> 
    property LeakData: TArray<TLeakItem> read FLeakData write FLeakData;
  end;

implementation

uses
  StrUtils,
  Command.Colors,
  Utils.IO;

constructor TLeakReport.Create;
begin
  SetLength(FLeakData, 0);
  FHeapDataIsMissing := True;
  FTotalLeakSize := 0;
  FTotalLeakInfo := '';
end;

destructor TLeakReport.Destroy;
var
  LItem: TLeakItem;
begin
  for LItem in FLeakData do
    LItem.Free;
  SetLength(FLeakData, 0);
  inherited Destroy;
end;

class function TLeakReport.New(ABuider: ICommandBuilder; const AProjectSource: string): TLeakReport;
begin
  Result := Self.Create;
  Result.ProjectSource := AProjectSource;
  Result.FBuilder := ABuider;
end;

function TLeakReport.AddItem(AItem: TLeakItem): TLeakItem;
begin
  SetLength(FLeakData, Length(FLeakData) + 1);
  FLeakData[Length(FLeakData) - 1] := AItem;
  Result := AItem;
end;

function TLeakReport.GetNextStringOf(const AText: string; const AField: string): string;
var
  LIndex: Integer;
  LValue: string;
begin
  LIndex := Pos(AField, AText);
  if LIndex <= 0 then
    exit('');

  LIndex := LIndex + Length(AField);
  LValue := Trim(Copy(AText, LIndex));
  Result := SplitString(LValue, ' ')[0];
end;

procedure TLeakReport.CreateLeakItem(AContent: TStringList; AStart: Integer);
var
  LText, LDetail: string;
  LItem: TLeakItem;
  I: Integer;
begin
  LText := AContent.Strings[AStart];
  if not ContainsText(LText, 'Call trace for block') then
    exit;

  LDetail := '';
  LItem := TLeakItem.New('Leak', GetNextStringOf(LText, 'size'));
  for I := AStart + 1 to AContent.Count - 1 do
  begin
    LText := AContent.Strings[I];
    if ContainsText(LText, 'Call trace for block') then
      break;

    if Length(LText) < 22 then
      continue;

    LText := Copy(LText, 20);
    LDetail := LDetail +
      StringReplace(GetNextStringOf(LText, ' '), ',', ' ', [rfReplaceAll]) +
      AddRelativePath(GetNextStringOf(LText, ' of ')) + ':' +
      GetNextStringOf(LText, 'line') + ':1' + #13#10;

  end;
  LItem.FSource := IfThen(LDetail = '', 'no details found in heap trace file.'#13#10, LDetail);
  AddItem(LItem);
end;

function TLeakReport.ParseHeapTrace(const AContent: string): TLeakReport;
var
  I: Integer;
  LContent: TStringList;
  LHeapFile, LText: string;
begin
  Result := Self;
  LContent := TStringList.Create;
  try
    LHeapFile := ConcatPaths([ProjectSource, 'heap.trc']);

    if (AContent = '') and FileExists(LHeapFile) then
      LContent.LoadFromFile(LHeapFile)
    else
      LContent.Text := AContent;

    for I := 0 to LContent.Count - 1 do
    begin
      LText := LContent.Strings[I];

      if ContainsText(LText, 'unfreed memory blocks') then
      begin
        FHeapDataIsMissing := False;
        FTotalLeakInfo := LText;
      end;

      if ContainsText(LText, 'Call trace for block') then
        CreateLeakItem(LContent, I);
    end;
  finally
    LContent.Free;
  end;
end;

procedure TLeakReport.Output;
var
  LItem: TLeakItem;
  LSourceItem, LOutputItem: string;
  LIndex: Integer;
begin
  FBuilder.OutputColor(PadLeft('Inspecting ', 13), FBuilder.ColorTheme.Value);
  FBuilder.OutputColor(
    'heap.trc file for possible leaks'#13#10, 
    FBuilder.ColorTheme.Other);

  if FHeapDataIsMissing then
  begin
    FBuilder.OutputColor(PadLeft('missing ', 13), FBuilder.ColorTheme.Title);
    FBuilder.OutputColor(
      'data with leak information'#13#10, 
      FBuilder.ColorTheme.Other);
    FBuilder.OutputColor('', StartupColor);
    Exit;
  end;

  if Length(FLeakData) = 0 then
  begin
    FBuilder.OutputColor(PadLeft('OK ', 13), FBuilder.ColorTheme.Value);
    FBuilder.OutputColor('[           0] 0 unfreed memory blocks.'#13#10, FBuilder.ColorTheme.Other);
    FBuilder.OutputColor(PadLeft('Summary ', 13), FBuilder.ColorTheme.Value);
    FBuilder.OutputColor('[           0] no memory leaks detected.'#13#10, FBuilder.ColorTheme.Other);
    FBuilder.Output('');
    Exit;
  end;
  
  for LItem in LeakData do
  begin
    FBuilder.OutputColor(PadLeft('Leak ', 13), LightRed);
    FBuilder.OutputColor('[' + PadLeft(LItem.Size, 12) + '] ', FBuilder.ColorTheme.Other);

    LIndex := 0;
    for LSourceItem in SplitString(LItem.Source, #10) do
    begin
      LOutputItem := StringReplace(LSourceItem, #13, '', [rfReplaceAll]);

      if Trim(LOutputItem) = '' then
        continue;  
      
      if LIndex > 0 then
        LOutputItem := StringOfChar(' ', 28) + LOutputItem;
      FBuilder.OutputColor(LOutputItem + #13#10, FBuilder.ColorTheme.Other);
      Inc(LIndex);
    end;
  end;

  FBuilder.OutputColor(PadLeft('Summary ', 13), FBuilder.ColorTheme.Value);
  FBuilder.OutputColor(
    '[' + PadLeft(IntToStr(FTotalLeakSize), 12) + ']', 
    FBuilder.ColorTheme.Other);
  FBuilder.OutputColor(' ' + FTotalLeakInfo, FBuilder.ColorTheme.Other);
  FBuilder.Output('');
end;

class function TLeakItem.New(const AStatus, ASize: string): TLeakItem;
begin
  Result := Self.Create;
  Result.Status := AStatus;
  Result.Size := ASize;
end;

function TLeakReport.AddRelativePath(const AFile: string): string;
var
  LRelativePath: string;
  LQualifiedPath: string;
begin
  // try to locate the file project source path
  LQualifiedPath := FindFile(ProjectSource, AFile);
  if LQualifiedPath = '' then
    LQualifiedPath := FindFile(GetCurrentDir, AFile);

  if LQualifiedPath = '' then
    LRelativePath := './'
  else
    LRelativePath := '.' + StringReplace(LQualifiedPath, GetCurrentDir, '', [rfReplaceAll, rfIgnoreCase]);

  Result := LRelativePath;
end;

end.
