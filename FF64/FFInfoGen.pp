program FFInfoGen;

//------------------------------------------------------------------------------------------------------------//
//                                                                                                            //
//  FFInfoGen 1.0 - FFmpeg info generator                                                                     //
//                                                                                                            //
//  The application generates a series of text files with detailed information about encoders, decoders,      //
//  muxers, demuxers and filters implemented in FFmpeg.                                                       //
//                                                                                                            //
//  IMPORTANT: ffmpeg.exe must be placed in folder with this script (or compiled executable).                 //
//                                                                                                            //
//------------------------------------------------------------------------------------------------------------//
//  You need InstantFPC (instantfpc.exe) and/or Free Pascal Compiler (fpc.exe) to run/compile this script.    //
//  http://wiki.freepascal.org/InstantFPC                                                                     //
//  http://www.freepascal.org/                                                                                //
//------------------------------------------------------------------------------------------------------------//
//                                                                                                            //
//      Geany tips:                                                                                           //
//        Compile command: instantfpc --skip-run -B "%f"                                                      //
//        Execute command: instantfpc "./%f"                                                                  //
//        Make command: fpc "%f"                                                                              //
//        Set bookmarks on regions.                                                                           //
//        In the file AppData\Roaming\geany\filetype_extensions.conf, in "Extensions" section add "*.pp" to   //
//        Pascal file type, eg. Pascal=*.pas;*.inc;*.dpr;*.dpk;*.lpr;*.dfm;*.lfm;*.pp                         //
//                                                                                                            //
//------------------------------------------------------------------------------------------------------------//
//                                                                                                            //
//  Script tested on Windows 10 with InstantFPC 1.3 (64-bit), FPC 3.1.1 (64-bit), 7-Zip 16.02 [64].           //
//                                                                                                            //
//  Tested FFmpeg versions:                                                                                   //
//                                                                                                            //
//    N-51106-g17c1881 (2013.03.19)                                                                           //
//    N-58590-g6e7de11 (2013.11.29)                                                                           //
//    N-63911-g3a1c895 (2014.06.12)                                                                           //
//    N-71609-g8f9a381 (2015.04.21)                                                                           //
//    N-80029-g42ee137 (2016.05.20)                                                                           //
//    N-82674-g1e7f9b0 (2016.11.29)                                                                           //
//                                                                                                            //
//------------------------------------------------------------------------------------------------------------//
//                                                                                                            //
//  License                                                                                                   //
//                                                                                                            //
//    The ExecConsoleApp function was written by Martin Lafferty (http://www.prel.co.uk).                     //
//    You can found original source at http://cc.embarcadero.com/item/14692                                   //
//    Martin has not provided any license information, but on Embarcadero's page it is copyrighted            //
//    as "No significant restrictions".                                                                       //
//    I have made some modifications to the needs of the FFInfoGen script/program.                            //
//                                                                                                            //
//    My (jp) code                                                                                            //
//      "Total free" - you can do with my code what you want.                                                 //
//                                                                                                            //
//------------------------------------------------------------------------------------------------------------//
//                                                                                                            //
//  jp, 2016.12.01                                                                                            //
//  http://www.pazera-software.com                                                                            //
//                                                                                                            //
//------------------------------------------------------------------------------------------------------------//

{$mode objfpc}{$H+}

uses
  Windows, SysUtils, Classes, fgl, crt;
  
  
// global CONST
const
  APP_NAME = 'FFInfoGen';
  APP_VER_STR = '1.0';
  APP_DATE = '2016.12.01';
  APP_FULL_NAME = APP_NAME + ' ' + APP_VER_STR;
  APP_AUTHOR = 'jp';
  APP_URL = 'http://www.pazera-software.com';
  
  HIDE_FF_BANNER = True;
  DISPLAY_CONSOLE_OUTPUT = False;
  SILENT = False;
  CR = #$0D;
  LF = #$0A;
  CRLF = CR + LF;
  ENDL = CRLF;
  EXIT_CODE_ERROR = 1;
  SEPLINE = '-------------------------------------------------------------------------------';
  INFO_FILE_PREFIX = 'ffmpeg_';
  
  ARR_INFO_SWITCHES: array[0..20] of string = (
    'h', 'h full', 'h long', 'version', 'L',
    'bsfs', 'codecs', 'encoders', 'decoders', 'filters', 'formats', 'layouts',
    'pix_fmts', 'protocols', 'sample_fmts', 'buildconf', 'devices', 'colors',
    'muxers', 'demuxers', 'hwaccels'
  );
  
  USE_COMPRESSION = True;
  CLEAR_DIRS_AFTER_COMPRESSION = False;
  COMPRESSION_LEVEL = 7; // 7-Zip compression level: 0 (none) - 9 (best)
  
  CON_BUF_SIZE = 10240;
  


// global TYPE
type
  TConsoleEvent = procedure(Process: THandle; const OutputLine: string);
  TIdList = specialize TFPGMap<string,string>;
  TIdListType = (iltEncoders, iltDecoders, iltMuxers, iltDemuxers, iltFilters);


// global VAR
var
  MyDir, ffmpeg, FFBanner: string;
  InfoDir, EncodersDir, DecodersDir, MuxersDir, DemuxersDir, FiltersDir: string;
  slOut: TStringList;
  SevenZip: string = '7z.exe'; // must be in the %PATH%
  CanHideBanner: Boolean;
  dtTime: TDateTime;


{$region ' --- ExecConsoleApp --- '}
//  The author of the original ExecConsoleApp function is Martin Lafferty (http://www.prel.co.uk , http://cc.embarcadero.com/item/14692).
//  I have made some modifications to the needs of the FFInfoGen script/program.
function ExecConsoleApp(const Exe, Parameters: string; OnNewLine: TConsoleEvent; CurrentDir: string = ''): DWORD;
const
  TerminationWaitTime = 5000;
var
  StartupInfo: TStartupInfo;
  ProcessInfo: TProcessInformation;
  SecurityAttributes: TSecurityAttributes;
  ThreadSecurityAttributes: TSecurityAttributes;
  TempHandle, WritePipe1, ReadPipe, WritePipe, WritePipe2: THandle;
  ReadBuf: array[0..CON_BUF_SIZE - 1] of AnsiChar;
  BytesRead: DWORD;
  LineBuf: array[0..CON_BUF_SIZE - 1] of AnsiChar;
  LineBufPtr: Integer;
  Newline: Boolean;
  i: Integer;
  CommandLine: string;
  //sOut: string;

  procedure OutputLine;
  begin
    LineBuf[LineBufPtr] := #0;
    Newline := False;
    LineBufPtr := 0;
    if Assigned(OnNewLine) then OnNewLine(ProcessInfo.hProcess, string(LineBuf));
  end;

begin
  Result := 1;

  if CurrentDir = '' then CurrentDir := ExtractFileDir(ParamStr(0));
  if CurrentDir = '' then CurrentDir := 'C:\';
  WritePipe := 0;

  CommandLine := Exe;
  if Trim(Parameters) <> '' then CommandLine := CommandLine + ' ' + Parameters;

  FillChar(StartupInfo, SizeOf(StartupInfo), 0);
  FillChar(ReadBuf, SizeOf(ReadBuf), 0);
  FillChar(SecurityAttributes, SizeOf(SecurityAttributes), 0);

  LineBufPtr := 0;
  Newline := True;

  SecurityAttributes.nLength := SizeOf(SecurityAttributes);
  SecurityAttributes.bInheritHandle := True;
  SecurityAttributes.lpSecurityDescriptor := nil;
  if not CreatePipe(ReadPipe, WritePipe1, @SecurityAttributes, 0) then RaiseLastOSError;

  ThreadSecurityAttributes.nLength := SizeOf(ThreadSecurityAttributes);
  ThreadSecurityAttributes.lpSecurityDescriptor := nil;
  
  try

    if Win32Platform = VER_PLATFORM_WIN32_NT then
      if not SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0) then RaiseLastOSError
      else
      begin
        if not DuplicateHandle(GetCurrentProcess, ReadPipe, GetCurrentProcess, @TempHandle, 0, True, DUPLICATE_SAME_ACCESS) then RaiseLastOSError;
        CloseHandle(ReadPipe);
        ReadPipe := TempHandle;
      end;

    ///////////////////////////////////////////////////////////////////////
    SecurityAttributes.nLength := SizeOf(SecurityAttributes);
    SecurityAttributes.bInheritHandle := True;
    SecurityAttributes.lpSecurityDescriptor := nil;
    CreatePipe(WritePipe2, WritePipe, @SecurityAttributes, 0);
    ///////////////////////////////////////////////////////////////////////

    with StartupInfo do
    begin
      cb := SizeOf(StartupInfo);
      dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
      wShowWindow := SW_HIDE;
      hStdInput := WritePipe2;
      hStdOutput := WritePipe1;
      hStdError := WritePipe1;
    end;

    if not CreateProcess(
      nil,
      PChar(CommandLine),
      nil,
      @ThreadSecurityAttributes,
      True,
      CREATE_NO_WINDOW or DETACHED_PROCESS,
      nil,
      PChar(CurrentDir),
      StartupInfo,
      ProcessInfo
      )
    then RaiseLastOSError;

    CloseHandle(WritePipe1);
    CloseHandle(WritePipe2);

    try
    
      while ReadFile(ReadPipe, ReadBuf, SizeOf(ReadBuf), BytesRead, nil) do
        for i := 0 to BytesRead - 1 do
        begin

          if (ReadBuf[i] = LF) then Newline := True
          else
            if (ReadBuf[i] = CR) then OutputLine
            else
            begin
              LineBuf[LineBufPtr] := ReadBuf[i];
              Inc(LineBufPtr);
              if LineBufPtr >= (SizeOf(LineBuf) - 1) then //line too long - force a break
              begin
                Newline := True;
                OutputLine;
              end;
            end;

        end; // for i

      WaitForSingleObject(ProcessInfo.hProcess, TerminationWaitTime);
      GetExitCodeProcess(ProcessInfo.hProcess, Result);
      OutputLine; //flush the line buffer

    finally
      CloseHandle(ProcessInfo.hProcess);
      CloseHandle(ProcessInfo.hThread);
    end


  finally
    CloseHandle(ReadPipe);
    CloseHandle(WritePipe);
  end;
end;
{$endregion ExecConsoleApp}
  
{$region ' --- ConsoleProc --- '}
procedure ConsoleProc(Process: THandle; const OutputLine: string);
begin
  //LastLine := OutputLine;
  slOut.Add(OutputLine);
  if DISPLAY_CONSOLE_OUTPUT then Writeln(OutputLine);
end;
{$endregion ConsoleProc}

{$region ' --- helpers --- '}
function IsFFCommandOK(const CmdParams: string): Boolean;
begin
  Result := ExecConsoleApp(ffmpeg, CmdParams, nil, '') = 0;
end;

procedure DisplayIdList(IdList: TIdList);
var
  i: integer;
begin
  for i := 0 to IdList.Count - 1 do
    Writeln('KEY: ', IdList.Keys[i], '              DATA: ', IdList.Data[i]);
end;

procedure SaveIdList(const fName: string; IdList: TIdList);
var
  i: integer;
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    for i := 0 to IdList.Count - 1 do
      sl.Add('KEY: ' + IdList.Keys[i] + '              DATA: ' + IdList.Data[i]);
    sl.SaveToFile(fName);
  finally
    sl.Free;
  end;
end;

procedure GetFFOutput(Params: string; var List: TStringList); overload;
var
  ExitCode: integer;
  i: integer;
  s: string;
begin
  slOut.Clear;
  ExitCode := ExecConsoleApp(ffmpeg, Params, @ConsoleProc, '');
  if ExitCode <> 0 then slOut.Clear;
  List.Assign(slOut);
end;

procedure GetFFOutput(Params: string; var ResStr: string); overload;
var
  ExitCode: integer;
  i: integer;
  s: string;
begin
  if not Assigned(slOut) then slOut := TStringList.Create;
  slOut.Clear;
  ExitCode := ExecConsoleApp(ffmpeg, Params, @ConsoleProc, '');
  if ExitCode <> 0 then ResStr := ''
  else ResStr := Trim(slOut.Text);
end;

function RemoveFFBanner(s: string): string;
begin
  Result := StringReplace(s, FFBanner, '', []);
end;

function GetFFBanner: string;
var
  ExitCode: integer;
  i, x: integer;
  s: string;
begin
  Result := '';
  if not Assigned(slOut) then slOut := TStringList.Create;
  slOut.Clear;
  ExitCode := ExecConsoleApp(ffmpeg, '-encoders', @ConsoleProc, '');
  if ExitCode <> 0 then Exit;
  x := slOut.IndexOf('Encoders:');
  if x <= 0 then Exit;
  for i := slOut.Count - 1 downto x do slOut.Delete(i);
  Result := slOut.Text;
end;
{$endregion helpers}

{$region ' --- ExitApp --- '}
procedure ExitApp(Msg: string; ExitCode: integer = EXIT_CODE_ERROR);
begin
  Writeln(SEPLINE);
  if Msg <> '' then Writeln(Msg);
  Write('Press ENTER to exit...');
  Readln;
  Halt(ExitCode);
end;
{$endregion ExitApp}

{$region ' --- QueryRun --- '}
procedure QueryRun;
var
  UserChoice: Char;
begin
  Writeln;
  Write('Press ''Q'' to quit or any other key to continue: ');
  UserChoice := ReadKey;
  Writeln;
  if UpCase(UserChoice) = 'Q' then
  begin
    Writeln('Bye!');
    Halt(0);
  end;
end;
{$endregion QueryRun}

{$region ' --- DisplayInfo --- '}
procedure DisplayInfo;
var
  i: integer;
  s: string;
  
  function BoolToStr(b: Boolean): string;
  begin
    if b then Result := 'Yes' else Result := 'No';
  end;
  
begin
  Writeln(APP_FULL_NAME);
  Writeln(APP_AUTHOR, ', ', APP_DATE);
  if APP_URL <> '' then Writeln(APP_URL);
  
  Writeln;
  Writeln(
    'The application generates a series of text files with detailed information about encoders, decoders, ' +
    'muxers, demuxers and filters implemented in FFmpeg.'
  );
  Writeln;
  
  Writeln('MyDir: ', MyDir);
  Writeln('ffmpeg: ', ffmpeg);
  Writeln('InfoDir: ', InfoDir);
  Writeln('EncodersDir: ', EncodersDir);
  Writeln('DecodersDir: ', DecodersDir);
  Writeln('MuxersDir: ', MuxersDir);
  Writeln('DemuxersDir: ', DemuxersDir);
  Writeln('FiltersDir: ', FiltersDir);
  
  Write('FFmpeg switches: ');
  s := '';
  for i := 0 to High(ARR_INFO_SWITCHES) do s := s + ', ' + ARR_INFO_SWITCHES[i];
  Delete(s, 1, 2);
  Writeln(s);
  
  Writeln('Hide FFmpeg banner: ', BoolToStr(HIDE_FF_BANNER));
  Writeln('7-Zip compression enabled: ', BoolToStr(USE_COMPRESSION));
  if USE_COMPRESSION then
  begin
    Writeln('7-Zip compression level: ', COMPRESSION_LEVEL);
    Writeln('Clean directories after compression: ', BoolToStr(CLEAR_DIRS_AFTER_COMPRESSION));
  end;
end;
{$endregion DisplayInfo}

{$region ' --- CreateDirs --- '}
procedure CreateDirs;
  procedure mkdir(const Dir: string); begin if not DirectoryExists(Dir) then CreateDir(Dir); end;
begin
  mkdir(InfoDir);
  mkdir(EncodersDir);
  mkdir(DecodersDir);
  mkdir(MuxersDir);
  mkdir(DemuxersDir);
  mkdir(FiltersDir);
end;
{$endregion CreateDirs}

{$region ' --- InitApp --- '}
procedure InitApp;
begin
  MyDir := ExtractFileDir(ExpandFileName('.' + PathDelim));
  ffmpeg := MyDir + PathDelim + 'ffmpeg.exe';
  if not FileExists(ffmpeg) then ExitApp('ffmpeg.exe must be in directory with ' + APP_NAME + ' script/executable!');
  InfoDir := MyDir + PathDelim + 'ffmpeg_info';
  EncodersDir := InfoDir + PathDelim + 'encoders';
  DecodersDir := InfoDir + PathDelim + 'decoders';
  MuxersDir := InfoDir + PathDelim + 'muxers';
  DemuxersDir := InfoDir + PathDelim + 'demuxers';
  FiltersDir := InfoDir + PathDelim + 'filters';
  CanHideBanner := IsFFCommandOK('-hide_banner -L');
  FFBanner := GetFFBanner;
  //Writeln(FFBanner); readln;
end;
{$endregion InitApp}

{$region ' --- CreateInfoFile --- '}
procedure CreateInfoFile(CmdParams: string; fName: string = '');
var
  s: string;
  ExitCode: integer;
begin
  if fName = '' then 
  begin
    s := CmdParams;
    if s = '-h' then s := 'HELP'
    else if s = '-h full' then s := 'HELP_full'
    else if s = '-h long' then s := 'HELP_long'
    else if s = '-version' then s := 'VERSION'
    else if s = '-buildconf' then s := 'BUILDCONF'
    else if s = '-pix_fmts' then s := 'pixel_formats'
    else if s = '-bsfs' then s := 'bitstreams'
    else if s = '-sample_fmts' then s := 'sample_formats'
    else if s = '-L' then s := 'LICENSE'
    else s := Copy(s, 2, Length(s) - 1);
    fName := InfoDir + PathDelim + INFO_FILE_PREFIX + s + '.txt';
  end;
  
  if not SILENT then Write('Creating file: ', fName); 
  if CanHideBanner and HIDE_FF_BANNER then CmdParams := '-hide_banner ' + CmdParams;
  slOut.Clear;
  ////////////////////////////////////////////////////////////////
  ExitCode := ExecConsoleApp(ffmpeg, CmdParams, @ConsoleProc, '');
  ////////////////////////////////////////////////////////////////
  if ExitCode = 0 then 
  begin
    if (not CanHideBanner) and HIDE_FF_BANNER and (s <> 'VERSION') then slOut.Text := RemoveFFBanner(slOut.Text);
    slOut.SaveToFile(fName);
    s := '  ... OK';
  end
  else s := '  ... error!';
  if not SILENT then Writeln(s);
end;
{$endregion CreateInfoFile}

{$region ' --- CreateBasicInfoFiles --- '}
procedure CreateBasicInfoFiles;
var
  i: integer;
begin
  for i := 0 to High(ARR_INFO_SWITCHES) do CreateInfoFile('-' + ARR_INFO_SWITCHES[i]);
end;
{$endregion CreateBasicInfoFiles}

{$region ' --- Process_EncodersDecoders --- '}
procedure Process_EncodersDecoders(IdListType: TIdListType);
const
  STR_UNKNOWN = 'trąbka';
var
  sl: TStringList;
  IdList: TIdList;
  i, x: integer;
  s, sName, sType, CmdParams, fOut: string;
  bSep: Boolean;
begin
  if (IdListType <> iltEncoders) and (IdListType <> iltDecoders) then Exit;
  
  sl := TStringList.Create;
  IdList := TIdList.Create;
  try
    if IdListType = iltEncoders then CmdParams := '-encoders'
    else CmdParams := '-decoders';
    if CanHideBanner then CmdParams := CmdParams + ' -hide_banner';
    GetFFOutput(CmdParams, sl);
    
    // usuwanie niepotrzebnych linii
    bSep := False;
    for i := sl.Count - 1 downto 0 do
    begin
      if bSep then 
      begin
        sl.Delete(i);
        Continue;
      end;
      s := Trim(sl[i]);
      if Copy(s, 1, 4) = '----' then
      begin
        bSep := True;
        sl.Delete(i);
        Continue;
      end
      else sl[i] := s;
    end; // for i
    
    // pobieranie informacji: encoder/decoder name + encoder/decoder type
    for i := 0 to sl.Count - 1 do
    begin
      s := sl[i];
      if s = '' then Continue;
      
      // encoder/decoder type
      sType := UpCase(s[1]);
      if sType = 'A' then sType := 'audio'
      else if sType = 'V' then sType := 'video'
      else if sType = 'S' then sType := 'subtitle'
      else sType := STR_UNKNOWN;
      if sType = STR_UNKNOWN then Continue;
      
      // encoder/decoder name
      sName := STR_UNKNOWN;
      x := Pos(' ', s);
      if x > 0 then
      begin
        s := Copy(s, x + 1, Length(s));
        x := Pos(' ', s);
        if x > 0 then sName := Copy(s, 1, x - 1);
      end;
      
      if (sName = STR_UNKNOWN) or (sType = STR_UNKNOWN) then Continue;
      
      IdList.Add(sName, sType);
    end; // for i
    
    //SaveIdList(MyDir + PathDelim + '_____idlist.txt', IdList);
    
    
    // creating info files
    sl.Clear;
    for i := 0 to IdList.Count - 1 do
    begin
      sName := IdList.Keys[i];
      sType := IdList.Data[i];
      if IdListType = iltEncoders then
      begin
        fOut := EncodersDir + PathDelim + sType + '_encoder_' + sName + '.txt';
        CmdParams := '--help encoder=' + sName;
      end
      else
      begin
        fOut := DecodersDir + PathDelim + sType + '_decoder_' + sName + '.txt';
        CmdParams := '--help decoder=' + sName;
      end;
      
      CreateInfoFile(CmdParams, fOut);
    end; // for i
    
  finally
    IdList.Free;
    sl.Free;
  end;
end;
{$endregion Process_EncodersDecoders}

{$region ' --- Process_Filters --- '}
procedure Process_Filters;
const
  STR_UNKNOWN = '';
var
  sl: TStringList;
  IdList: TIdList;
  i, x: integer;
  s, sName, sType, CmdParams, fOut: string;
  bOldFFmpeg: Boolean;
begin
  
  sl := TStringList.Create;
  IdList := TIdList.Create;
  try
    CmdParams := '-filters';
    if CanHideBanner then CmdParams := CmdParams + ' -hide_banner';
    GetFFOutput(CmdParams, sl);
    
    // usuwanie niepotrzebnych linii
    x := -1;
    for i := 0 to sl.Count - 1 do
    begin
      s := sl[i];
      if (Pos('->', s) > 0) then
      begin
        x := i - 1;
        Break;
      end;
    end;
    if x > 0 then
      for i := x downto 0 do sl.Delete(i);
    
    
    // pobieranie informacji: filter name + filter type (eg. A->A)
    
    // OLD FFmpeg: "aformat          A->A       Convert the input audio to one of the specified formats."
    // NEW FFmpeg: " ... aformat           A->A       Convert the input audio to one of the specified formats."
    bOldFFmpeg := False;
    if sl.Count > 0 then bOldFFmpeg := Copy(sl[0], 1, 1) <> ' ';
    
    // No filters info for old ffmpeg versions???
    if not bOldFFmpeg then
    begin

      for i := 0 to sl.Count - 1 do
      begin
      
        s := Trim(sl[i]);
        if s = '' then Continue;
        
        x := Pos(' ', s);
        if x > 0 then s := Trim(Copy(s, x + 1, Length(s)))
        else Continue;
        
        sName := STR_UNKNOWN;
        sType := STR_UNKNOWN;
        
        
        x := Pos(' ', s);
        if x > 0 then
        begin
          sName := Copy(s, 1, x - 1);
          s := Trim(Copy(s, x + 1, Length(s)));
          x := Pos(' ', s);
          if x > 0 then sType := Copy(s, 1, x - 1);
        end;
        
        if (sName = STR_UNKNOWN) or (sType = STR_UNKNOWN) then Continue;
        
        sType := StringReplace(sType, '>', '-', [rfReplaceAll]);
        sType := StringReplace(sType, '|', 'I', [rfReplaceAll]);
        
        IdList.Add(sName, sType);
        
      end; // for i
      
      //DisplayIdList(IdList);
      //SaveIdList(MyDir + PathDelim + '_____idlist.txt', IdList);
      
      
      // creating info files
      sl.Clear;
      for i := 0 to IdList.Count - 1 do
      begin
        sName := IdList.Keys[i];
        sType := IdList.Data[i];

        fOut := FiltersDir + PathDelim + 'filter_' + sName + '_' + sType + '.txt';
        CmdParams := '--help filter=' + sName;

        CreateInfoFile(CmdParams, fOut);
      end; // for i
    
    
    end; // if not bOldFFmpeg
    
  finally
    IdList.Free;
    sl.Free;
  end;
end;
{$endregion Process_Filters}

{$region ' --- Process_MuxersDemuxers --- '}
procedure Process_MuxersDemuxers(IdListType: TIdListType);
var
  sl: TStringList;
  i, x: integer;
  s, sName, CmdParams, fOut, sID: string;
  bSep, bOldFFmpeg: Boolean;
  
  function TryGetMDName(Line, MDID: string; var MDName: string): Boolean; // searching muxer/demuxer name
  var
    s4: string;
    x: integer;
  begin
    Result := False;
    if Length(Line) < 5 then Exit;
    if (Line[1] <> ' ') or (Line[4] <> ' ') or (Line[5] = '=') then Exit;
    s4 := Copy(Line, 1, 4);
    if Pos(MDID, s4) = 0 then Exit;
    Line := Trim(Line);
    x := Pos(' ', Line);
    if x = 0 then Exit;
    Line := Trim(Copy(Line, x + 1, Length(s)));
    x := Pos(' ', Line);
    if x = 0 then Exit;
    MDName := Copy(Line, 1, x - 1);
    Result := True;
  end;
  
begin
  if (IdListType <> iltMuxers) and (IdListType <> iltDemuxers) then Exit;
  
  if IdListType = iltMuxers then sID := 'E' else sID := 'D';
  
  bOldFFmpeg := not IsFFCommandOK('-muxers');
  
  // Old FFmpeg does not supports "-muxers" switch. We must parse formats.
  if bOldFFmpeg then CmdParams := '-formats' else
  
    // New versions of the FFmpeg supports "-muxers" and "-demuxers" switches
    if IdListType = iltMuxers then CmdParams := '-muxers' else CmdParams := '-demuxers';
    
  if CanHideBanner then CmdParams := CmdParams + ' -hide_banner';
  
  
  sl := TStringList.Create;
  try
  
    GetFFOutput(CmdParams, sl);
    
    // creating list with muxer/demuxer names
    for i := sl.Count - 1 downto 0 do
    begin
      s := sl[i];
      if not TryGetMDName(s, sID, sName) then
      begin
        sl.Delete(i);
        Continue;
      end;
      sl[i] := sName;
    end; // for i
    
    //sl.SaveToFile(MyDir + PathDelim + 'sl.txt');
    
    // creating info files
    for i := 0 to sl.Count - 1 do
    begin
      sName := sl[i];
      if IdListType = iltMuxers then
      begin
        fOut := MuxersDir + PathDelim + 'muxer_' + sName + '.txt';
        CmdParams := '--help muxer=' + sName;
      end
      else
      begin
        fOut := DemuxersDir + PathDelim + 'demuxer_' + sName + '.txt';
        CmdParams := '--help demuxer=' + sName;
      end;
      
      CreateInfoFile(CmdParams, fOut);
    end; // for i
    
  finally
    sl.Free;
  end;
end;
{$endregion Process_MuxersDemuxers}

{$region ' --- CompressFiles --- '}
procedure CompressFiles;
var
  Exe, CmdParams, ArchFile, s: string;
  ExitCode: integer;
begin
  Exe := SevenZip;
  ArchFile := MyDir + PathDelim + 'ffmpeg_info.7z';
  CmdParams := 'a -r -t7z -m0=LZMA2 -mx=' + COMPRESSION_LEVEL.ToString + ' -mmt=2 -mtm=on -mtc=on -mta=on';
  if CLEAR_DIRS_AFTER_COMPRESSION then CmdParams := CmdParams + ' -sdel';
  CmdParams := CmdParams + ' "' + ArchFile + '" "' + InfoDir + PathDelim + '*"';
  if FileExists(ArchFile) then DeleteFile(ArchFile);
  slOut.Clear;
  Writeln(SEPLINE);
  Write('Compressing ... ');
  ExitCode := ExecConsoleApp(Exe, CmdParams, @ConsoleProc, '');
  if ExitCode = 0 then s := 'OK' else s := 'error';
  Writeln(s);
  Writeln('7-Zip output:');
  Writeln(slOut.Text);
  if CLEAR_DIRS_AFTER_COMPRESSION then RemoveDir(InfoDir);
end;
{$endregion CompressFiles}

{$region ' --- RemoveEmptyDirs --- '}
procedure RemoveEmptyDirs;
begin
  RemoveDir(FiltersDir);
  RemoveDir(MuxersDir);
  RemoveDir(DemuxersDir);
  RemoveDir(EncodersDir);
  RemoveDir(DecodersDir);
  RemoveDir(InfoDir);
end;
{$endregion RemoveEmptyDirs}


{$region ' -------- ENTRY POINT -------- '}
begin

  InitApp;
  DisplayInfo;
  QueryRun;
  CreateDirs;
  dtTime := Now;
  
  if not Assigned(slOut) then slOut := TStringList.Create;
  try

    Writeln(SEPLINE);
    CreateBasicInfoFiles;
    
    Process_EncodersDecoders(iltEncoders);
    Process_EncodersDecoders(iltDecoders);
    Process_MuxersDemuxers(iltMuxers);
    Process_MuxersDemuxers(iltDemuxers);
    Process_Filters;
    
    RemoveEmptyDirs;

    if USE_COMPRESSION then CompressFiles;
    

  finally
    slOut.Free;
  end;
  
  Writeln(SEPLINE);
  Writeln('Elapsed time ' + TimeToStr(Now - dtTime));
  ExitApp('', 0);
  
end.
{$endregion ENTRY POINT}
