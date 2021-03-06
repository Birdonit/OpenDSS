unit Solution;
{
  ----------------------------------------------------------
  Copyright (c) 2008-2015, Electric Power Research Institute, Inc.
  All rights reserved.
  ----------------------------------------------------------
}

{ Change Log
 8-14-99 Added progress display and abort on longer solution types
 11-3-99 added calc voltage base
 11-21-99 modified to  calc the voltage bases at the current load level set by the user.
 12-1-99 Added code to estimate starting point for P-V Generators
 12-2-99 Made more properties visible
 12-6-99 Merged properties with Set Command and removed from here
 12-15-99 Added global generatordispatchreference
 1-8-00   Fixed bug in autoadd generators to work with new generator model
          set vminpu=0 and vmaxpu=1000000
 1-30-00 to 2-1-00 Implemented control action check in solution
 2-19-00 Frequency changed reset to FALSE after being used (was causing all YPrims to be recomputed)
 2-23-00 Modified so that reset of meters and monitors is done upon setting the solution mode property.
         After that the user must reset else the monitors just accumulate.
 3-20-00 Fixed bug with setting generator disp reference - made uniform for all types
 6-11-00 Split into two modules + moved auto add stuff to AutoAdd
 9-20-00 Added Dynamic Mode
 10-25-00 Added Fundamental Freq and other stuff for Harmonics Solution
 5-30-01  Added control iterations check, mostIterationsdone.
          Fixed bug with controls off doing the solution too many times.

 8-14-01 Reset IntervalHrs on Mode change
 7-11-02 Added check for system Y change after computing currents

 9-28-03 Redefined V to NodeV and changed from an array from 1..n to 0..n where
         0-th element is alway ground(complex zero volts).
 8-14-06 Revised power flow initialization; removed forward/backward sweep

}

interface

USES
    uCOMPLEX, Arraydef,
    Command,
    Monitor,
    DSSClass,
    DSSObject,
    Dynamics,
    EnergyMeter,
    SysUtils,
    System.Diagnostics,
    System.TimeSpan,
    System.Classes,
    Parallel_Lib;

CONST

     NORMALSOLVE = 0;
     NEWTONSOLVE = 1;

TYPE

   EControlProblem = class(Exception);
   ESolveError = Class(Exception);  // Raised when solution aborted

   TNodeVarray = Array[0..1000] of Complex;
   pNodeVarray = ^TNodeVarray;

   TDSSSolution = CLASS(TDSSClass)
     private
//       CommandList:TCommandlist;
     Protected
       PROCEDURE DefineProperties;
     public
       constructor Create;
       destructor Destroy; override;

       FUNCTION Edit(ActorID : Integer):Integer; override;
       FUNCTION Init(Handle:Integer; ActorID : Integer):Integer; override;
       FUNCTION NewObject(const ObjName:String):Integer; override;

   End;
   TInfoMessageCall = Procedure(const info:String) of object;  // Creates the procedure for sending a message
   TSolver=class(TThread)
      Constructor Create(Susp:Boolean;local_CPU: integer; ID : integer; CallBack: TInfoMessageCall);overload;
      procedure Execute; override;
//*******************************Private components*****************************
    private
      FMessage  : String;
      FInfoProc : TInfoMessageCall;
      Msg_Cmd   : string;
      ActorID   : integer;
//*******************************Public components******************************
    Public
      procedure CallCallBack;
   end;

   TSolutionObj = class(TDSSObject)
     private

       dV :pNodeVArray;   // Array of delta V for Newton iteration
       FFrequency:Double;
       Process  : TThread;

       FUNCTION Converged(ActorID : Integer):Boolean;
       FUNCTION OK_for_Dynamics(const Value:Integer):Boolean;
       FUNCTION OK_for_Harmonics(const Value:Integer):Boolean;



       PROCEDURE DoNewtonSolution(ActorID : Integer);
       PROCEDURE DoNormalSolution(ActorID : Integer);
//       PROCEDURE GetMachineInjCurrents;
       PROCEDURE SetGeneratordQdV(ActorID : Integer);
       PROCEDURE SumAllCurrents;
       procedure Set_Frequency(const Value: Double);
       PROCEDURE Set_Mode(const Value: Integer);
       procedure Set_Year(const Value: Integer);
       procedure Set_Total_Time(const Value: Double);

     public

       Algorithm :Integer;      // NORMALSOLVE or NEWTONSOLVE
       AuxCurrents  :pComplexArray;  // For injections like AutoAdd
       ControlActionsDone :Boolean;
       ControlIteration :Integer;
       ControlMode :Integer;     // EVENTDRIVEN, TIMEDRIVEN
       ConvergenceTolerance :Double;
       ConvergedFlag:Boolean;
       DefaultControlMode :Integer;    // EVENTDRIVEN, TIMEDRIVEN
       DefaultLoadModel :Integer;     // 1=POWERFLOW  2=ADMITTANCE
       DoAllHarmonics : Boolean;
       DynamicsAllowed :Boolean;
       DynaVars:TDynamicsRec;
       ErrorSaved :pDoubleArray;
       FirstIteration :Boolean;
       FrequencyChanged:Boolean;  // Flag set to true if something has altered the frequency
       Fyear :Integer;
       Harmonic   :Double;
       HarmonicList  :pDoubleArray;
       HarmonicListSize :Integer;
       hYsystem :NativeUint;   {Handle for main (system) Y matrix}
       hYseries :NativeUint;   {Handle for series Y matrix}
       hY :NativeUint;         {either hYsystem or hYseries}
       IntervalHrs:Double;   // Solution interval since last solution, hrs.
       IsDynamicModel :Boolean;
       IsHarmonicModel :Boolean;
       Iteration :Integer;
       LoadModel :Integer;        // 1=POWERFLOW  2=ADMITTANCE
       LastSolutionWasDirect :Boolean;
       LoadsNeedUpdating :Boolean;
       MaxControlIterations :Integer;
       MaxError :Double;
       MaxIterations :Integer;
       MostIterationsDone :Integer;
       NodeVbase :pDoubleArray;
       NumberOfTimes :Integer;  // Number of times to solve
       PreserveNodeVoltages:Boolean;
       RandomType :Integer;     //0 = none; 1 = gaussian; 2 = UNIFORM
       SeriesYInvalid :Boolean;
       SolutionCount :Integer;  // Counter incremented for each solution
       SolutionInitialized :Boolean;
       SystemYChanged  : Boolean;
       UseAuxCurrents  : Boolean;
       VmagSaved : pDoubleArray;
       VoltageBaseChanged : Boolean;

        {Voltage and Current Arrays}
       NodeV    : pNodeVArray;    // Main System Voltage Array   allows NodeV^[0]=0
       Currents : pNodeVArray;      // Main System Currents Array

//****************************Timing variables**********************************
       SolveStartTime      : int64;
       SolveEndtime        : int64;
       GStartTime     : int64;
       Gendtime       : int64;
       LoopEndtime            : int64;
       Total_Time_Elapsed     : double;
       Solve_Time_Elapsed     : double;
       Total_Solve_Time_Elapsed  : double;
       Step_Time_Elapsed      : double;
//******************************************************************************

       constructor Create(ParClass:TDSSClass; const solutionname:String);
       destructor  Destroy; override;

       PROCEDURE ZeroAuxCurrents;
       FUNCTION  SolveZeroLoadSnapShot(ActorID : Integer) :Integer;
       PROCEDURE DoPFLOWsolution(ActorID : Integer);

       PROCEDURE Solve(ActorID : Integer);                // Main Solution dispatch
       PROCEDURE SnapShotInit(ActorID : Integer);
       FUNCTION  SolveSnap(ActorID : integer):Integer;    // solve for now once
       FUNCTION  SolveDirect(ActorID : integer):Integer;  // solve for now once, direct solution
       FUNCTION  SolveYDirect(ActorID : Integer):Integer; // Similar to SolveDirect; used for initialization
       FUNCTION  SolveCircuit(ActorID : integer):Integer; // SolveSnap sans control iteration
       PROCEDURE CheckControls(ActorID : Integer);       // Snapshot checks with matrix rebuild
       PROCEDURE SampleControlDevices(ActorID : Integer);
       PROCEDURE DoControlActions(ActorID : Integer);
       PROCEDURE Sample_DoControlActions(ActorID : Integer);    // Sample and Do
       PROCEDURE Check_Fault_Status(ActorID : Integer);

       PROCEDURE SetGeneratorDispRef(ActorID : Integer);
       PROCEDURE SetVoltageBases(ActorID : Integer);

       PROCEDURE SaveVoltages;
       PROCEDURE UpdateVBus; // updates voltages for each bus    from NodeV
       PROCEDURE RestoreNodeVfromVbus;  // opposite   of updatebus

       FUNCTION  VDiff(i,j:Integer):Complex;  // Difference between two node voltages

       PROCEDURE InitPropertyValues(ArrayOffset:Integer);Override;
       PROCEDURE DumpProperties(Var F:TextFile; Complete:Boolean); Override;
       PROCEDURE WriteConvergenceReport(const Fname:String);
       PROCEDURE Update_dblHour;
       PROCEDURE Increment_time;

       PROCEDURE UpdateLoopTime;

       Property  Mode         :Integer  Read dynavars.SolutionMode Write Set_Mode;
       Property  Frequency    :Double   Read FFrequency            Write Set_Frequency;
       Property  Year         :Integer  Read FYear                 Write Set_Year;
       Property  Time_Solve :Double  Read Solve_Time_Elapsed;
       Property  Time_TotalSolve:Double  Read Total_Solve_Time_Elapsed;
       Property  Time_Step:Double      Read Step_Time_Elapsed;     // Solve + sample
       Property  Total_Time   :Double  Read Total_Time_Elapsed      Write Set_Total_Time;

 // Procedures that use to be private before 01-20-2016

       PROCEDURE AddInAuxCurrents(SolveType:Integer; ActorID : Integer);
       Function SolveSystem(V:pNodeVArray; ActorID : Integer):Integer;
       PROCEDURE GetPCInjCurr(ActorID : Integer);
       PROCEDURE GetSourceInjCurrents(ActorID : Integer);
       PROCEDURE ZeroInjCurr(ActorID : Integer);

   End;


{==========================================================================}


VAR
   ActiveSolutionObj:TSolutionObj;


implementation

USES  SolutionAlgs,
      DSSClassDefs, DSSGlobals, DSSForms, CktElement,  ControlElem, Fault,
      Executive, AutoAdd,  YMatrix,
      ParserDel, Generator,
{$IFDEF DLL_ENGINE}
      ImplGlobals,  // to fire events
{$ENDIF}
      Math,  Circuit, Utilities, KLUSolve, Windows, ScriptEdit
;

Const NumPropsThisClass = 1;

{$DEFINE debugtrace}

{$UNDEF debugtrace}  {turn it off  delete this line to activate debug trace}

{$IFDEF debugtrace}
var FDebug:TextFile;
{$ENDIF}


// ===========================================================================================
constructor TDSSSolution.Create;  // Collection of all solution objects
Begin
     Inherited Create;
     Class_Name := 'Solution';
     DSSClassType := DSS_OBJECT + HIDDEN_ELEMENT;

     ActiveElement := 0;

     DefineProperties;

     CommandList := TCommandList.Create(Slice(PropertyName^, NumProperties));
     CommandList.Abbrev := True;


End;

// ===========================================================================================
Destructor TDSSSolution.Destroy;

Begin
    // ElementList and  CommandList freed in inherited destroy
    Inherited Destroy;

End;

// ===========================================================================================
PROCEDURE TDSSSolution.DefineProperties;
Begin

     Numproperties := NumPropsThisClass;
     CountProperties;   // Get inherited property count
     AllocatePropertyArrays;


     // Define Property names
     PropertyName[1] := '-------';


     // define Property help values
     PropertyHelp[1] := 'Use Set Command to set Solution properties.';


     ActiveProperty := NumPropsThisClass;
     inherited DefineProperties;  // Add defs of inherited properties to bottom of list

End;


// ===========================================================================================
FUNCTION TDSSSolution.NewObject(const ObjName:String):Integer;
Begin
    // Make a new Solution Object and add it to Solution class list
      ActiveSolutionObj := TSolutionObj.Create(Self, ObjName);
    // this one is different than the rest of the objects.
      Result := AdDobjectToList(ActiveSolutionObj);
End;

// ===========================================================================================
constructor TSolutionObj.Create(ParClass:TDSSClass; const SolutionName:String);
// ===========================================================================================
Begin
    Inherited Create(ParClass);
    Name := LowerCase(SolutionName);

//    i := SetLogFile ('c:\\temp\\KLU_Log.txt', 1);

    FYear    := 0;
    DynaVars.intHour     := 0;
    DynaVars.t        := 0.0;
    DynaVars.dblHour  := 0.0;
    DynaVars.tstart   := 0.0;
    DynaVars.tstop    := 0.0;
    //duration := 0.0;
    DynaVars.h        := 0.001;  // default for dynasolve

    LoadsNeedUpdating := TRUE;
    VoltageBaseChanged := TRUE;  // Forces Building of convergence check arrays

    MaxIterations    := 15;
    MaxControlIterations  := 10;
    ConvergenceTolerance := 0.0001;
    ConvergedFlag := FALSE;

    IsDynamicModel   := FALSE;
    IsHarmonicModel  := FALSE;

    Frequency := DefaultBaseFreq;
    {Fundamental := 60.0; Moved to Circuit and used as default base frequency}
    Harmonic := 1.0;

    FrequencyChanged := TRUE;  // Force Building of YPrim matrices
    DoAllHarmonics   := TRUE;
    FirstIteration   := TRUE;
    DynamicsAllowed  := FALSE;
    SystemYChanged   := TRUE;
    SeriesYInvalid   := TRUE;

    {Define default harmonic list}
    HarmonicListSize := 5;
    HarmonicList := AllocMem(SizeOf(harmonicList^[1])*HarmonicListSize);
    HarmonicList^[1] := 1.0;
    HarmonicList^[2] := 5.0;
    HarmonicList^[3] := 7.0;
    HarmonicList^[4] := 11.0;
    HarmonicList^[5] := 13.0;

    SolutionInitialized := FALSE;
    LoadModel        := POWERFLOW;
    DefaultLoadModel := LoadModel;
    LastSolutionWasDirect := False;

    hYseries := 0;
    hYsystem := 0;
    hY := 0;

    NodeV      := nil;
    dV         := nil;
    Currents   := nil;
    AuxCurrents:= nil;
    VMagSaved  := nil;
    ErrorSaved := nil;
    NodeVbase  := nil;

    UseAuxCurrents := FALSE;

    SolutionCount := 0;

    Dynavars.SolutionMode := SNAPSHOT;
    ControlMode           := CTRLSTATIC;
    DefaultControlMode    := ControlMode;
    Algorithm             := NORMALSOLVE;

    RandomType    := GAUSSIAN;  // default to gaussian
    NumberOfTimes := 100;
    IntervalHrs   := 1.0;

    InitPropertyValues(0);

End;

// ===========================================================================================
destructor TSolutionObj.Destroy;
Begin
      Reallocmem(AuxCurrents, 0);
      Reallocmem(Currents, 0);
      Reallocmem(dV, 0);
      Reallocmem(ErrorSaved, 0);
      Reallocmem(NodeV, 0);
      Reallocmem(NodeVbase, 0);
      Reallocmem(VMagSaved, 0);

      If hYsystem <> 0 THEN   DeleteSparseSet[ActiveActor](hYsystem);
      If hYseries <> 0 THEN   DeleteSparseSet[ActiveActor](hYseries);

//      SetLogFile ('c:\\temp\\KLU_Log.txt', 0);

      Reallocmem(HarmonicList,0);

      Inherited Destroy;
End;


// ===========================================================================================
FUNCTION TDSSSolution.Edit(ActorID : Integer):Integer;

Begin
     Result := 0;

     ActiveSolutionObj := ActiveCircuit[ActorID].Solution;

     WITH ActiveSolutionObj Do Begin

       // This is all we do here now...
         Solve(ActorID);

     End;  {WITH}
End;


// ===========================================================================================
PROCEDURE TSolutionObj.Solve(ActorID : Integer);
var
  ScriptEd  : TScriptEdit;

Begin

     ActiveCircuit[ActorID].Issolved := False;
     SolutionWasAttempted   := TRUE;

{Check of some special conditions that must be met before executing solutions}

    If ActiveCircuit[ActorID].EmergMinVolts >= ActiveCircuit[ActorID].NormalMinVolts Then  Begin
            DoSimpleMsg('Error: Emergency Min Voltage Must Be Less Than Normal Min Voltage!' +
                         CRLF + 'Solution Not Executed.', 480);
            Exit;
    End;

    If SolutionAbort Then  Begin
         GlobalResult:= 'Solution aborted.';
         CmdResult := SOLUTION_ABORT;
         ErrorNumber := CmdResult;
         Exit;
    End;


Try

{Main solution Algorithm dispatcher}

    WITH ActiveCircuit[ActorID] Do  Begin
    
       CASE Year of
         0:  DefaultGrowthFactor := 1.0;    // RCD 8-17-00
       ELSE
           DefaultGrowthFactor := IntPower(DefaultGrowthRate, (year-1));
       END;
    End;

{$IFDEF DLL_ENGINE}
    Fire_InitControls;
{$ENDIF}

    {CheckFaultStatus;  ???? needed here??}
     QueryPerformanceCounter(GStartTime);
{
     Case Dynavars.SolutionMode OF
         SNAPSHOT:     SolveSnap;
         YEARLYMODE:   SolveYearly;
         DAILYMODE:    SolveDaily;
         DUTYCYCLE:    SolveDuty;
         DYNAMICMODE:  SolveDynamic;
         MONTECARLO1:  SolveMonte1;
         MONTECARLO2:  SolveMonte2;
         MONTECARLO3:  SolveMonte3;
         PEAKDAY:      SolvePeakDay;
         LOADDURATION1:SolveLD1;
         LOADDURATION2:SolveLD2;
         DIRECT:       SolveDirect;
         MONTEFAULT:   SolveMonteFault;  // Monte Carlo Fault Cases
         FAULTSTUDY:   SolveFaultStudy;
         AUTOADDFLAG:  ActiveCircuit[ActiveActor].AutoAddObj.Solve;
         HARMONICMODE: SolveHarmonic;
         GENERALTIME:  SolveGeneralTime;
         HARMONICMODET:SolveHarmonicT;  //Declares the Hsequential-time harmonics
     Else
         DosimpleMsg('Unknown solution mode.', 481);
     End;
}
    if ActorHandle[ActorID] <> nil  then ActorHandle[ActorID].Free;
    ActorHandle[ActorID] :=  TSolver.Create(false,ActorCPU[ActorID],ActorID,ScriptEd.UpdateSummaryForm);
Except

    On E:Exception Do Begin
       DoSimpleMsg('Error Encountered in Solve: ' + E.Message, 482);
       SolutionAbort := TRUE;
    End;

End;

End;

// ===========================================================================================
FUNCTION TSolutionObj.Converged(ActorID : Integer):Boolean;

VAR
  i:Integer;
  VMag:Double;

Begin

// base convergence on voltage magnitude

    MaxError := 0.0;
    FOR i := 1 to ActiveCircuit[ActorID].NumNodes Do  Begin
      
        VMag := Cabs(NodeV^[i]);

    { If base specified, use it; otherwise go on present magnitude  }
        If      NodeVbase^[i] > 0.0 Then ErrorSaved^[i] := Abs(Vmag - VmagSaved^[i])/NodeVbase^[i]
        Else If Vmag <> 0.0         Then ErrorSaved^[i] := Abs(1.0 - VmagSaved^[i]/Vmag);

        VMagSaved^[i] := Vmag;  // for next go-'round

        MaxError := Max(MaxError, ErrorSaved^[i]);  // update max error

    End;

{$IFDEF debugtrace}
              Assignfile(Fdebug, 'Debugtrace.csv');
              Append(FDebug);
              If Iteration=1 Then Begin
                Write(Fdebug,'Iter');
                For i := 1 to ActiveCircuit[ActorID].NumNodes Do
                    Write(Fdebug, ', ', ActiveCircuit[ActorID].Buslist.get(ActiveCircuit[ActorID].MapNodeToBus^[i].BusRef), '.', ActiveCircuit[ActiveActor].MapNodeToBus^[i].NodeNum:0);
                Writeln(Fdebug);
              End;
              {*****}
                Write(Fdebug,Iteration:2);
                For i := 1 to ActiveCircuit[ActorID].NumNodes Do
                    Write(Fdebug, ', ', VMagSaved^[i]:8:1);
                Writeln(Fdebug);
                Write(Fdebug,'Err');
                For i := 1 to ActiveCircuit[ActorID].NumNodes Do
                    Write(Fdebug, ', ', Format('%-.5g',[ErrorSaved^[i]]));
                Writeln(Fdebug);
                Write(Fdebug,'Curr');
                For i := 1 to ActiveCircuit[ActorID].NumNodes Do
                    Write(Fdebug, ', ', Cabs(Currents^[i]):8:1);
                Writeln(Fdebug);
              {*****}
                CloseFile(FDebug);
{$ENDIF};

    IF MaxError <= ConvergenceTolerance THEN Result := TRUE
                                        ELSE Result := FALSE;

    ConvergedFlag := Result;
End;


// ===========================================================================================
PROCEDURE TSolutionObj.GetSourceInjCurrents(ActorID : Integer);

// Add in the contributions of all source type elements to the global solution vector InjCurr

VAR
   pElem:TDSSCktElement;

Begin

  WITH ActiveCircuit[ActorID]
  Do Begin

     pElem := Sources.First;
     WHILE pElem<>nil
     Do Begin
       IF pElem.Enabled THEN pElem.InjCurrents(ActorID); // uses NodeRef to add current into InjCurr Array;
       pElem := Sources.Next;
     End;

  End;

End;

// ===========================================================================================
PROCEDURE TSolutionObj.SetGeneratorDispRef(ActorID : Integer);

// Set the global generator dispatch reference

Begin
    WITH ActiveCircuit[ActorID] Do
    Case Dynavars.SolutionMode OF
    
         SNAPSHOT:     GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor;
         YEARLYMODE:   GeneratorDispatchReference := DefaultGrowthFactor * DefaultHourMult.re;
         DAILYMODE:    GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor * DefaultHourMult.re;
         DUTYCYCLE:    GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor * DefaultHourMult.re;
         GENERALTIME:  GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor * DefaultHourMult.re;
         DYNAMICMODE:  GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor;
         HARMONICMODE: GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor;
         MONTECARLO1:  GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor;
         MONTECARLO2:  GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor * DefaultHourMult.re;
         MONTECARLO3:  GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor * DefaultHourMult.re;
         PEAKDAY:      GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor * DefaultHourMult.re;
         LOADDURATION1:GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor * DefaultHourMult.re;
         LOADDURATION2:GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor * DefaultHourMult.re;
         DIRECT:       GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor;
         MONTEFAULT:   GeneratorDispatchReference := 1.0;  // Monte Carlo Fault Cases solve  at peak load only base case
         FAULTSTUDY:   GeneratorDispatchReference := 1.0;
         AUTOADDFLAG:  GeneratorDispatchReference := DefaultGrowthFactor;   // peak load only
         HARMONICMODET: GeneratorDispatchReference := LoadMultiplier * DefaultGrowthFactor * DefaultHourMult.re;
     Else
         DosimpleMsg('Unknown solution mode.', 483);
     End;
End;
// ===========================================================================================
PROCEDURE TSolutionObj.SetGeneratordQdV(ActorID : Integer);

Var
   pGen  :TGeneratorObj;
   Did_One : Boolean;
   GenDispSave :Double;

Begin
     Did_One := False;

     // Save the generator dispatch level and set on high enough to
     // turn all generators on
     GenDispSave := ActiveCircuit[ActorID].GeneratorDispatchReference;
     ActiveCircuit[ActorID].GeneratorDispatchReference := 1000.0;

     WITH ActiveCircuit[ActorID] Do Begin
     
         pGen := Generators.First;
         WHILE pGen <> nil Do Begin
         
           If pGen.Enabled Then Begin

              // for PV generator models only ...
              If pGen.genModel = 3 Then Begin
              
                   pGen.InitDQDVCalc;

                   // solve at base var setting
                   Iteration := 0;
                   Repeat
                       Inc(Iteration);
                       ZeroInjCurr(ActorID);
                       GetSourceInjCurrents(ActorID);
                       pGen.InjCurrents(ActorID);   // get generator currents with nominal vars
                       SolveSystem(NodeV, ActorID);
                   Until Converged(ActorID) or (Iteration >= Maxiterations);

                   pGen.RememberQV(ActorID);  // Remember Q and V
                   pGen.BumpUpQ;

                   // solve after changing vars
                   Iteration := 0;
                   Repeat
                       Inc(Iteration);
                       ZeroInjCurr(ActorID);
                       GetSourceInjCurrents(ActorID);
                       pGen.InjCurrents(ActorID);   // get generator currents with nominal vars
                       SolveSystem(NodeV, ActorID);
                   Until Converged(ActorID) or (Iteration >= Maxiterations);

                   pGen.CalcdQdV(ActorID); // bssed on remembered Q and V and present values of same
                   pGen.ResetStartPoint;

                   Did_One := True;
              End;
          End;
          pGen := Generators.Next;
         End;

     End;

     // Restore generator dispatch reference
     ActiveCircuit[ActorID].GeneratorDispatchReference := GenDispSave;
    TRY
       If Did_One        // Reset Initial Solution
       THEN  SolveZeroLoadSnapShot(ActorID);
    EXCEPT
        ON E:EEsolv32Problem Do Begin
          DoSimpleMsg('From SetGenerator DQDV, SolveZeroLoadSnapShot: ' + CRLF + E.Message  + CheckYMatrixforZeroes(ActorID), 7071);
          Raise ESolveError.Create('Aborting');
        End;
    End;

End;

// ===========================================================================================
PROCEDURE TSolutionObj.DoNormalSolution(ActorID : Integer);

{ Normal fixed-point solution

   Vn+1 = [Y]-1 Injcurr

   Where Injcurr includes only PC elements  (loads, generators, etc.)
   i.e., the shunt elements.

   Injcurr are the current injected INTO the NODE
        (need to reverse current direction for loads)
}

Begin


   Iteration := 0;

 {**** Main iteration loop ****}
   With ActiveCircuit[ActorID] Do
   Repeat
       Inc(Iteration);

       If LogEvents Then LogThisEvent('Solution Iteration ' + IntToStr(Iteration));

    { Get injcurrents for all PC devices  }
       ZeroInjCurr(ActorID);
       GetSourceInjCurrents(ActorID);  // sources
       GetPCInjCurr(ActorID);  // Get the injection currents from all the power conversion devices and feeders

       // The above call could change the primitive Y matrix, so have to check
        IF SystemYChanged THEN BuildYMatrix(WHOLEMATRIX, FALSE, ActorID);  // Does not realloc V, I

        IF UseAuxCurrents THEN AddInAuxCurrents(NORMALSOLVE, ActorID);

      // Solve for voltages                      {Note:NodeV[0] = 0 + j0 always}
       If LogEvents Then LogThisEvent('Solve Sparse Set DoNormalSolution ...');
       SolveSystem(NodeV, ActorID);
       LoadsNeedUpdating := FALSE;

   Until (Converged(ActorID) and (Iteration > 1)) or (Iteration >= MaxIterations);


End;


// ===========================================================================================
PROCEDURE TSolutionObj.DoNewtonSolution(ActorID : Integer);

{ Newton Iteration

   Vn+1 =  Vn - [Y]-1 Termcurr

   Where Termcurr includes currents from all elements and we are
   attempting to get the  currents to sum to zero at all nodes.

   Termcurr is the sum of all currents going INTO THE TERMINALS of
   the elements.

   For PD Elements, Termcurr = Yprim*V

   For Loads, Termcurr = (Sload/V)*
   For Generators, Termcurr = -(Sgen/V)*

}

Var
   i    :Integer;

Begin

   WITH ActiveCircuit[ActorID] Do
   Begin
       ReAllocMem(dV, SizeOf(dV^[1]) * (NumNodes+1)); // Make sure this is always big enough

       IF   ControlIteration = 1
       THEN GetPCInjCurr(ActorID);  // Update the load multipliers for this solution
       
       Iteration := 0;
       REPEAT
           Inc(Iteration);
           Inc(SolutionCount);    // SumAllCurrents Uses ITerminal  So must force a recalc

        // Get sum of currents at all nodes for all  devices
           ZeroInjCurr(ActorID);
           SumAllCurrents;

           // Call to current calc could change YPrim for some devices
           IF SystemYChanged THEN BuildYMatrix(WHOLEMATRIX, FALSE, ActorID);   // Does not realloc V, I

           IF UseAuxCurrents THEN AddInAuxCurrents(NEWTONSOLVE, ActorID);

        // Solve for change in voltages
           SolveSystem(dV, ActorID);

           LoadsNeedUpdating := FALSE;

         // Compute new guess at voltages
           FOR i := 1 to NumNodes Do     // 0 node is always 0
           WITH NodeV^[i] Do
           Begin
                re := re - dV^[i].re;
                im := im - dV^[i].im;
           End;

       UNTIL (Converged(ActorID) and (Iteration > 1)) or (Iteration >= MaxIterations);
    End;
End;


// ===========================================================================================
PROCEDURE TSolutionObj.DoPFLOWsolution(ActorID : Integer);


Begin

   Inc(SolutionCount);    //Unique number for this solution

   If VoltageBaseChanged Then  InitializeNodeVbase(ActorID); // for convergence test

   IF Not SolutionInitialized THEN Begin
     
        If ActiveCircuit[ActorID].LogEvents Then LogThisEvent('Initializing Solution');
      TRY
        //SolveZeroLoadSnapShot;
        SolveYDirect(ActorID);  // 8-14-06 This should give a better answer than zero load snapshot
      EXCEPT
        ON E:EEsolv32Problem Do Begin
          DoSimpleMsg('From DoPFLOWsolution.SolveYDirect: ' + CRLF + E.Message  + CheckYMatrixforZeroes(ActorID), 7072);
          Raise ESolveError.Create('Aborting');
        End;
      END;
        If SolutionAbort Then Exit; // Initialization can result in abort

      TRY
        SetGeneratordQdV(ActorID);  // Set dQdV for Model 3 generators
      EXCEPT
        ON E:EEsolv32Problem Do Begin
          DoSimpleMsg('From DoPFLOWsolution.SetGeneratordQdV: ' + CRLF + E.Message  + CheckYMatrixforZeroes(ActorID), 7073);
          Raise ESolveError.Create('Aborting');
        End;
      END;

        { The above resets the active sparse set to hY }
        SolutionInitialized := True;
   End;


   CASE Algorithm of
      NORMALSOLVE: DoNormalSolution(ActorID);
      NEWTONSOLVE: DoNewtonSolution(ActorID);
   End;

   ActiveCircuit[ActorID].Issolved := ConvergedFlag;
   LastSolutionWasDirect := False;

End;

// ===========================================================================================
FUNCTION TSolutionObj.SolveZeroLoadSnapShot(ActorID : Integer):Integer;

// Solve without load for initialization purposes;

Begin
   Result := 0;

    IF SystemYChanged OR SeriesYInvalid THEN BuildYMatrix(SERIESONLY, TRUE, ActorID);   // Side Effect: Allocates V

    Inc(SolutionCount);    //Unique number for this solution

    ZeroInjCurr(ActorID);   // Side Effect: Allocates InjCurr
    GetSourceInjCurrents(ActorID);    // Vsource, Isource and VCCS only

    {Make the series Y matrix the active matrix}
    IF  hYseries = 0 THEN
        Raise EEsolv32Problem.Create('Series Y matrix not built yet in SolveZeroLoadSnapshot.');
    hY := hYseries;

    If ActiveCircuit[ActiveActor].LogEvents Then LogThisEvent('Solve Sparse Set ZeroLoadSnapshot ...');

    SolveSystem(NodeV, ActorID);  // also sets voltages in radial part of the circuit if radial solution

    { Reset the main system Y as the solution matrix}
    IF   (hYsystem > 0) and Not SolutionAbort THEN
      hY := hYsystem;
End;

// ===========================================================================================
PROCEDURE  TSolutionObj.SetVoltageBases(ActorID : Integer);

// Set voltage bases using voltage at first node (phase) of a bus

Var
  i:Integer;
  bZoneCalc, bZoneLock: Boolean;

Begin

  TRY
    // don't allow the meter zones to auto-build in this load flow solution, because the
    // voltage bases are not available yet

    bZoneCalc := ActiveCircuit[ActorID].MeterZonesComputed;
    bZoneLock := ActiveCircuit[ActorID].ZonesLocked;
    ActiveCircuit[ActorID].MeterZonesComputed := True;
    ActiveCircuit[ActorID].ZonesLocked := True;

    SolveZeroLoadSnapShot(ActorID);

    WITH ActiveCircuit[ActorID] Do
      FOR i := 1 to NumBuses Do
        WITH Buses^[i] Do
          kVBase := NearestBasekV( Cabs(NodeV^[GetRef(1)]) * 0.001732) / SQRT3;  // l-n base kV

    InitializeNodeVbase(ActorID);      // for convergence test

    ActiveCircuit[ActorID].Issolved := True;

    // now build the meter zones
    ActiveCircuit[ActorID].MeterZonesComputed := bZoneCalc;
    ActiveCircuit[ActorID].ZonesLocked := bZoneLock;
    ActiveCircuit[ActorID].DoResetMeterZones(ActorID);

  EXCEPT
    ON E:EEsolv32Problem Do Begin
      DoSimpleMsg('From SetVoltageBases.SolveZeroLoadSnapShot: ' + CRLF + E.Message  + CheckYMatrixforZeroes(ActorID), 7075);
      Raise ESolveError.Create('Aborting');
    End;
  END;

End;

PROCEDURE TSolutionObj.SnapShotInit(ActorID : Integer);

Begin

   SetGeneratorDispRef(ActorID);
   ControlIteration   := 0;
   ControlActionsDone := False;
   MostIterationsDone := 0;
   LoadsNeedUpdating := TRUE;  // Force the loads to update at least once

End;

PROCEDURE TSolutionObj.CheckControls(ActorID : Integer);

Begin
      If ControlIteration < MaxControlIterations then Begin
           IF ConvergedFlag Then Begin
               If ActiveCircuit[ActorID].LogEvents Then LogThisEvent('Control Iteration ' + IntToStr(ControlIteration));
               Sample_DoControlActions(ActorID);
               Check_Fault_Status(ActorID);
           End
           ELSE
               ControlActionsDone := TRUE; // Stop solution process if failure to converge
       End;

       IF SystemYChanged THEN BuildYMatrix(WHOLEMATRIX, FALSE, ActorID); // Rebuild Y matrix, but V stays same
End;

// ===========================================================================================
FUNCTION TSolutionObj.SolveSnap(ActorID : integer):Integer;  // solve for now once

VAR
   TotalIterations  :Integer;

Begin
   SnapShotInit(ActorID);
   TotalIterations    := 0;
   QueryPerformanceCounter(SolveStartTime);
   REPEAT

       Inc(ControlIteration);

       Result := SolveCircuit(ActorID);  // Do circuit solution w/o checking controls

       {Now Check controls}
{$IFDEF DLL_ENGINE}
       Fire_CheckControls;
{$ENDIF}
       CheckControls(ActorID);

       {For reporting max iterations per control iteration}
       If Iteration > MostIterationsDone  THEN MostIterationsDone := Iteration;

       TotalIterations := TotalIterations + Iteration;

   UNTIL ControlActionsDone or (ControlIteration >= MaxControlIterations);

   If Not ControlActionsDone and (ControlIteration >= MaxControlIterations) then  Begin
       DoSimpleMsg('Warning Max Control Iterations Exceeded. ' + CRLF + 'Tip: Show Eventlog to debug control settings.', 485);
       SolutionAbort := TRUE;   // this will stop this message in dynamic power flow modes
   End;

   If ActiveCircuit[ActorID].LogEvents Then LogThisEvent('Solution Done');

{$IFDEF DLL_ENGINE}
   Fire_StepControls;
{$ENDIF}
   QueryPerformanceCounter(SolveEndtime);
   Solve_Time_Elapsed := ((SolveEndtime-SolveStartTime)/CPU_Freq)*1000000;
   Iteration := TotalIterations;  { so that it reports a more interesting number }

End;

// ===========================================================================================
FUNCTION TSolutionObj.SolveDirect(ActorID : integer):Integer;  // solve for now once, direct solution

Begin
   Result := 0;

   LoadsNeedUpdating := TRUE;  // Force possible update of loads and generators
   QueryPerformanceCounter(SolveStartTime);

   If SystemYChanged THEN BuildYMatrix(WHOLEMATRIX, TRUE, ActorID);   // Side Effect: Allocates V

   Inc(SolutionCount);   // Unique number for this solution

   ZeroInjCurr(ActorID);   // Side Effect: Allocates InjCurr
   GetSourceInjCurrents(ActorID);

   // Pick up PCELEMENT injections for Harmonics mode and Dynamics mode
   // Ignore these injections for powerflow; Use only admittance in Y matrix
   If IsDynamicModel or IsHarmonicModel Then  GetPCInjCurr(ActorID);

   IF   SolveSystem(NodeV, ActorID) = 1   // Solve with Zero injection current
   THEN Begin
       ActiveCircuit[ActorID].IsSolved := TRUE;
       ConvergedFlag := TRUE;
   End;

   QueryPerformanceCounter(SolveEndtime);
   Solve_Time_Elapsed  := ((SolveEndtime-SolveStartTime)/CPU_Freq)*1000000;
   Total_Time_Elapsed  :=  Total_Time_Elapsed + Solve_Time_Elapsed;
   Iteration := 1;
   LastSolutionWasDirect := TRUE;

End;


function TSolutionObj.SolveCircuit(ActorID : integer): Integer;
begin

       Result := 0;
       IF LoadModel=ADMITTANCE
       Then
            TRY
              SolveDirect(ActorID)     // no sense horsing around when it's all admittance
            EXCEPT
                ON E:EEsolv32Problem
                Do Begin
                  DoSimpleMsg('From SolveSnap.SolveDirect: ' + CRLF + E.Message  + CheckYMatrixforZeroes(ActorID), 7075);
                  Raise ESolveError.Create('Aborting');
                End;
            END
       Else  Begin
           TRY
              IF SystemYChanged THEN BuildYMatrix(WHOLEMATRIX, TRUE, ActorID);   // Side Effect: Allocates V
              DoPFLOWsolution(ActorID);
           EXCEPT
             ON E:EEsolv32Problem
             Do Begin
               DoSimpleMsg('From SolveSnap.DoPflowSolution: ' + CRLF + E.Message  + CheckYMatrixforZeroes(ActorID), 7074);
               Raise ESolveError.Create('Aborting');
             End;
           END
       End;

end;

// ===========================================================================================
PROCEDURE TSolutionObj.ZeroInjCurr(ActorID : Integer);
VAR
    I:Integer;
Begin
    FOR i := 0 to ActiveCircuit[ActorID].NumNodes Do Currents^[i] := CZERO;
End;

//----------------------------------------------------------------------------
FUNCTION TDSSSolution.Init(Handle:Integer; ActorID : Integer):Integer;

Begin
   DoSimpleMsg('Need to implement TSolution.Init', -1);
   Result := 0;
End;


// ===========================================================================================
PROCEDURE TSolutionObj.GetPCInjCurr(ActorID : Integer);
  VAR
     pElem:TDSSCktElement;

{ Get inj currents from all enabled PC devices }

Begin

  WITH ActiveCircuit[ActorID]
  Do Begin
     pElem := PCElements.First;
     WHILE pElem <> nil
     Do Begin
       WITH pElem Do IF Enabled  THEN InjCurrents(ActorID); // uses NodeRef to add current into InjCurr Array;
       pElem := PCElements.Next;
     End;
   End;

End;

PROCEDURE TSolutionObj.DumpProperties(Var F:TextFile; complete:Boolean);

VAR
   i,j              :Integer;

   // for dumping the matrix in compressed columns
   p                :LongWord;
   hY, nBus, nNZ    :LongWord;
   ColPtr, RowIdx   :array of LongWord;
   cVals            :array of Complex;
Begin

  Writeln(F, '! OPTIONS');

  // Inherited DumpProperties(F,Complete);

  Writeln(F, '! NumNodes = ',ActiveCircuit[ActiveActor].NumNodes:0);

    {WITH ParentClass Do
     FOR i := 1 to NumProperties Do
     Begin
        Writeln(F,'Set ',PropertyName^[i],'=',PropertyValue^[i]);
     End;
     }
     Writeln(F, 'Set Mode=', GetSolutionModeID);
     Writeln(F, 'Set ControlMode=', GetControlModeID);
     Writeln(F, 'Set Random=', GetRandomModeID);
     Writeln(F, 'Set hour=',   DynaVars.intHour:0);
     Writeln(F, 'Set sec=',    Format('%-g', [DynaVars.t]));
     Writeln(F, 'Set year=',   Year:0);
     Writeln(F, 'Set frequency=',   Format('%-g',[Frequency]));
     Writeln(F, 'Set stepsize=',    Format('%-g', [DynaVars.h]));
     Writeln(F, 'Set number=',   NumberOfTimes:0);
     Writeln(F, 'Set circuit=',  ActiveCircuit[ActiveActor].Name);
     Writeln(F, 'Set editor=',   DefaultEditor);
     Writeln(F, 'Set tolerance=', Format('%-g', [ConvergenceTolerance]));
     Writeln(F, 'Set maxiter=',   MaxIterations:0);
     Writeln(F, 'Set loadmodel=', GetLoadModel);

     Writeln(F, 'Set loadmult=',    Format('%-g', [ActiveCircuit[ActiveActor].LoadMultiplier]));
     Writeln(F, 'Set Normvminpu=',  Format('%-g', [ActiveCircuit[ActiveActor].NormalMinVolts]));
     Writeln(F, 'Set Normvmaxpu=',  Format('%-g', [ActiveCircuit[ActiveActor].NormalMaxVolts]));
     Writeln(F, 'Set Emergvminpu=', Format('%-g', [ActiveCircuit[ActiveActor].EmergMinVolts]));
     Writeln(F, 'Set Emergvmaxpu=', Format('%-g', [ActiveCircuit[ActiveActor].EmergMaxVolts]));
     Writeln(F, 'Set %mean=',   Format('%-.4g', [ActiveCircuit[ActiveActor].DefaultDailyShapeObj.Mean * 100.0]));
     Writeln(F, 'Set %stddev=', Format('%-.4g', [ActiveCircuit[ActiveActor].DefaultDailyShapeObj.StdDev * 100.0]));
     Writeln(F, 'Set LDCurve=', ActiveCircuit[ActiveActor].LoadDurCurve);  // Load Duration Curve
     Writeln(F, 'Set %growth=', Format('%-.4g', [((ActiveCircuit[ActiveActor].DefaultGrowthRate-1.0)*100.0)]));  // default growth rate
     With ActiveCircuit[ActiveActor].AutoAddObj Do
     Begin
       Writeln(F, 'Set genkw=', Format('%-g', [GenkW]));
       Writeln(F, 'Set genpf=', Format('%-g', [GenPF]));
       Writeln(F, 'Set capkvar=', Format('%-g', [Capkvar]));
       Write(F, 'Set addtype=');
       Case Addtype of
          GENADD:Writeln(F,'generator');
          CAPADD:Writeln(F,'capacitor');
       End;
     End;
     Write(F, 'Set allowduplicates=');
     If  ActiveCircuit[ActiveActor].DuplicatesAllowed THEN Writeln(F, 'Yes') ELSE Writeln(F,'No');
     Write(F, 'Set zonelock=');
     IF ActiveCircuit[ActiveActor].ZonesLocked THEN Writeln(F, 'Yes') ELSE Writeln(F,'No');
     Writeln(F, 'Set ueweight=',    ActiveCircuit[ActiveActor].UEWeight:8:2);
     Writeln(F, 'Set lossweight=',  ActiveCircuit[ActiveActor].LossWeight:8:2);
     Writeln(F, 'Set ueregs=',   IntArraytoString(ActiveCircuit[ActiveActor].UEregs,   ActiveCircuit[ActiveActor].NumUERegs));
     Writeln(F, 'Set lossregs=', IntArraytoString(ActiveCircuit[ActiveActor].Lossregs, ActiveCircuit[ActiveActor].NumLossRegs));
     Write(F, 'Set voltagebases=(');  //  changes the default voltage base rules
     i:=1;
     WITH ActiveCircuit[ActiveActor] Do
     WHILE LegalVoltageBases^[i] > 0.0 Do
     Begin
         Write(F, LegalVoltageBases^[i]:10:2);
         inc(i);
     End;
     Writeln(F,')');
     Case Algorithm of
       NORMALSOLVE: Writeln(F, 'Set algorithm=normal');
       NEWTONSOLVE: Writeln(F, 'Set algorithm=newton');
     End;
     Write(F,'Set Trapezoidal=');
     IF   ActiveCircuit[ActiveActor].TrapezoidalIntegration
     THEN Writeln(F, 'yes')
     ELSE Writeln(F, 'no');
     Writeln(F, 'Set genmult=', Format('%-g', [ActiveCircuit[ActiveActor].GenMultiplier]));

     Writeln(F, 'Set Basefrequency=', Format('%-g', [ActiveCircuit[ActiveActor].Fundamental]));

     Write(F, 'Set harmonics=(');  //  changes the default voltage base rules
       IF DoAllHarmonics Then Write(F, 'ALL')
       ELSE FOR i := 1 to HarmonicListSize Do Write(F, Format('%-g, ', [HarmonicList^[i]]));
     Writeln(F,')');
     Writeln(F, 'Set maxcontroliter=',  MaxControlIterations:0);
     Writeln(F);

  If Complete THEN With ActiveCircuit[ActiveActor] Do Begin

      hY := Solution.hY;

      // get the compressed columns out of KLU
      FactorSparseMatrix[ActiveActor](hY); // no extra work if already done
      GetNNZ[ActiveActor](hY, @nNZ);
      GetSize[ActiveActor](hY, @nBus);
      SetLength (ColPtr, nBus + 1);
      SetLength (RowIdx, nNZ);
      SetLength (cVals, nNZ);
      GetCompressedMatrix[ActiveActor](hY, nBus + 1, nNZ, @ColPtr[0], @RowIdx[0], @cVals[0]);

      Writeln(F,'System Y Matrix (Lower Triangle by Columns)');
      Writeln(F);
      Writeln(F,'  Row  Col               G               B');
      Writeln(F);

      // traverse the compressed column format
      for j := 0 to nBus - 1 do begin /// the zero-based column
        for p := ColPtr[j] to ColPtr[j+1] - 1
        do begin
              i := RowIdx[p];  // the zero-based row
              Writeln (F, Format('[%4d,%4d] = %12.5g + j%12.5g', [i+1, j+1, cVals[p].re, cVals[p].im]));
        end;
      end;
  End;
End;

FUNCTION TSolutionObj.VDiff(i,j:Integer):Complex;

Begin
    Result := Csub(NodeV^[i], NodeV^[j]);  // V1-V2
End;


PROCEDURE TSolutionObj.WriteConvergenceReport(const Fname:String);
Var
   i:Integer;
   F:TextFile;
Begin
   TRY
     Assignfile(F,Fname);
     ReWrite(F);

     Writeln(F);
     Writeln(F,'-------------------');
     Writeln(F, 'Convergence Report:');
     Writeln(F,'-------------------');
     Writeln(F,'"Bus.Node", "Error", "|V|","Vbase"');
     WITH ActiveCircuit[ActiveActor] Do
       FOR i := 1 to NumNodes Do
         WITH MapNodeToBus^[i]   Do
         Begin
              Write(F, '"', pad((BusList.Get(Busref)+'.'+IntToStr(NodeNum)+'"'), 18) );
              Write(F,', ', ErrorSaved^[i]:10:5);
              Write(F,', ', VmagSaved^[i]:14);
              Write(F,', ', NodeVbase^[i]:14);
              Writeln(F);
         End;

    Writeln(F);
    Writeln(F, 'Max Error = ', MaxError:10:5);

  FINALLY

     CloseFile(F);
     FireOffEditor(Fname);

  End;

End;

// =========================================================================================== =
PROCEDURE TSolutionObj.SumAllCurrents;

Var
   pelem :TDSSCktElement;

begin
     WITH  ActiveCircuit[ActiveActor] Do
       Begin
          pelem := CktElements.First;
          WHILE pelem <> nil Do
          Begin
              pelem.SumCurrents ;   // sum terminal currents into system Currents Array
              pelem := CktElements.Next;
          End;
       End;
end;

// =========================================================================================== =
PROCEDURE TSolutionObj.DoControlActions(ActorID : Integer);
VAR
   XHour:Integer;
   XSec :Double;
Begin
    With ActiveCircuit[ActorID] Do
      Begin
          CASE ControlMode of

              CTRLSTATIC:
                 Begin  //  execute the nearest set of control actions but leaves time where it is
                      IF   ControlQueue.IsEmpty
                      THEN ControlActionsDone := TRUE
                      ELSE ControlQueue.DoNearestActions(xHour, XSec, ActorID); // ignore time advancement
                 End;
              EVENTDRIVEN:
                 Begin  //  execute the nearest set of control actions and advance time to that time
                 // **** Need to update this to set the "Intervalhrs" variable for EnergyMeters for Event-Driven Simulation ****
                      IF NOT ControlQueue.DoNearestActions(DynaVars.intHour, DynaVars.t, ActorID) // these arguments are var type
                      THEN ControlActionsDone := TRUE;// Advances time to the next event
                 End;
              TIMEDRIVEN:
                 Begin   // Do all actions having an action time <= specified time
                      IF NOT ControlQueue.DoActions (DynaVars.intHour, DynaVars.t, ActorID)
                      THEN ControlActionsDone := TRUE;
                 End;

          END;
      End;

End;

// =========================================================================================== =
PROCEDURE TSolutionObj.SampleControlDevices(ActorID : Integer);

Var
    ControlDevice:TControlElem;

Begin
    With ActiveCircuit[ActorID] Do Begin
          ControlDevice := Nil;
          TRY
            // Sample all controls and set action times in control Queue
            ControlDevice := DSSControls.First;
            WHILE ControlDevice <> Nil Do
            Begin
                 IF ControlDevice.Enabled THEN ControlDevice.Sample(ActorID);
                 ControlDevice := DSSControls.Next;
            End;

          EXCEPT
             On E: Exception DO  Begin
             DoSimpleMsg(Format('Error Sampling Control Device "%s.%s" %s  Error = %s',[ControlDevice.ParentClass.Name, ControlDevice.Name, CRLF, E.message]), 484);
             Raise EControlProblem.Create('Solution aborted.');
             End;
          END;
    End;

End;

// =========================================================================================== =
PROCEDURE TSolutionObj.Sample_DoControlActions(ActorID : Integer);



begin

     IF ControlMode = CONTROLSOFF THEN ControlActionsDone := TRUE
     ELSE  Begin

          SampleControlDevices(ActorID);
          DoControlActions(ActorID);

     {This variable lets control devices know the bus list has changed}
         ActiveCircuit[ActorID].Control_BusNameRedefined := False;  // Reset until next change
     End;

end;

PROCEDURE TSolutionObj.Set_Mode(const Value: Integer);


begin

   DynaVars.intHour       := 0;
   DynaVars.t    := 0.0;
   Update_dblHour;
   ActiveCircuit[ActiveActor].TrapezoidalIntegration := FALSE;

   IF Not OK_for_Dynamics(Value)  Then Exit;
   IF Not OK_for_Harmonics(Value) Then Exit;

   Dynavars.SolutionMode := Value;

   ControlMode := DefaultControlMode;   // Revert to default mode
   LoadModel   := DefaultLoadModel;

   IsDynamicModel  := FALSE;
   IsHarmonicModel := FALSE;

   SolutionInitialized := FALSE;   // reinitialize solution when mode set (except dynamics)
   PreserveNodeVoltages := FALSE;  // don't do this unless we have to

   // Reset defaults for solution modes
   Case Dynavars.SolutionMode of

       PEAKDAY,
       DAILYMODE:     Begin
                           DynaVars.h    := 3600.0;
                           NumberOfTimes := 24;
                      End;
       SNAPSHOT:      Begin
                           IntervalHrs   := 1.0;
                           NumberOfTimes := 1;
                      End;
       YEARLYMODE:    Begin
                           IntervalHrs   := 1.0;
                           DynaVars.h    := 3600.0;
                           NumberOfTimes := 8760;
                      End;
       DUTYCYCLE:     Begin
                           DynaVars.h  := 1.0;
                           ControlMode := TIMEDRIVEN;
                      End;
       DYNAMICMODE:   Begin
                           DynaVars.h     := 0.001;
                           ControlMode    := TIMEDRIVEN;
                           IsDynamicModel := TRUE;
                           PreserveNodeVoltages := TRUE;  // need to do this in case Y changes during this mode
                      End;
       GENERALTIME:   Begin
                           IntervalHrs   := 1.0;
                           DynaVars.h    := 3600.0;
                           NumberOfTimes := 1;  // just one time step per Solve call expected
                      End;
       MONTECARLO1:   Begin IntervalHrs    := 1.0;  End;
       MONTECARLO2:   Begin DynaVars.h     := 3600.0;   End;
       MONTECARLO3:   Begin IntervalHrs    := 1.0;   End;
       MONTEFAULT:    Begin IsDynamicModel := TRUE;  END;
       FAULTSTUDY:    Begin
                            IsDynamicModel := TRUE;
                      END;
       LOADDURATION1: Begin
                           DynaVars.h := 3600.0;
                           ActiveCircuit[ActiveActor].TrapezoidalIntegration := TRUE;
                      End;
       LOADDURATION2: Begin
                           DynaVars.intHour := 1;
                           ActiveCircuit[ActiveActor].TrapezoidalIntegration := TRUE;
                      End;
       AUTOADDFLAG :  Begin
                           IntervalHrs := 1.0;
                           ActiveCircuit[ActiveActor].AutoAddObj.ModeChanged := TRUE;
                      End;
       HARMONICMODE:  Begin
                          ControlMode     := CONTROLSOFF;
                          IsHarmonicModel := TRUE;
                          LoadModel       := ADMITTANCE;
                          PreserveNodeVoltages := TRUE;  // need to do this in case Y changes during this mode
                      End;
       HARMONICMODET: Begin
                          IntervalHrs   := 1.0;
                          DynaVars.h    := 3600.0;
                          NumberOfTimes := 1;
                          ControlMode     := CONTROLSOFF;
                          IsHarmonicModel := TRUE;
                          LoadModel       := ADMITTANCE;
                          PreserveNodeVoltages := TRUE;  // need to do this in case Y changes during this mode
       End;
   End;

   {Moved here 9-8-2007 so that mode is changed before reseting monitors, etc.}
   
   // Reset Meters and Monitors
   MonitorClass[ActiveActor].ResetAll(ActiveActor);
   EnergyMeterClass[ActiveActor].ResetAll(ActiveActor);
   DoResetFaults;
   DoResetControls;

end;

PROCEDURE TSolutionObj.AddInAuxCurrents(SolveType:Integer; ActorID : Integer);

BEGIN
    {FOR i := 1 to ActiveCircuit[ActiveActor].NumNodes Do Caccum(Currents^[i], AuxCurrents^[i]);}
    // For Now, only AutoAdd Obj uses this

    IF Dynavars.SolutionMode = AUTOADDFLAG THEN ActiveCircuit[ActiveActor].AutoAddObj.AddCurrents(SolveType, ActorID);

END;

PROCEDURE TSolutionObj.ZeroAuxCurrents;
VAR i:Integer;
BEGIN
    FOR i := 1 to ActiveCircuit[ActiveActor].NumNodes Do AuxCurrents^[i] := CZERO;
END;

PROCEDURE TSolutionObj.Check_Fault_Status(ActorID : Integer);

VAR
   pFault:TFaultOBj;

begin
     WITH ActiveCircuit[ActorID]
     Do Begin
       
          pFault := TFaultObj(Faults.First);
          WHILE pFault <> NIL
          Do Begin
             pFault.CheckStatus(ControlMode, ActorID);
             pFault := TFaultObj(Faults.Next);
          End;

     End;  {End With}
end;


{ This procedure is called for Solve Direct and any other solution method
  that does not get the injection currents for PC elements normally. In Dynamics mode,
  Generators are voltage sources ...

Procedure TSolutionObj.GetMachineInjCurrents;

Var
  pElem:TDSSCktElement;

begin
     // do machines in Dynamics Mode
     IF   IsDynamicModel THEN
      With ActiveCircuit[ActiveActor] DO  Begin

         pElem := Generators.First;
         WHILE pElem<>nil Do Begin
             IF pElem.Enabled THEN pElem.InjCurrents; // uses NodeRef to add current into InjCurr Array;
             pElem := Generators.Next;
         End;

       End;

end;
}

FUNCTION TSolutionObj.OK_for_Dynamics(Const Value:Integer): Boolean;

VAR
   ValueIsDynamic :Boolean;

begin

   Result := TRUE;

   CASE Value of
        MONTEFAULT,
        DYNAMICMODE,
        FAULTSTUDY: ValueIsDynamic := TRUE;
   ELSE
       ValueIsDynamic := FALSE;
   END;

   {When we go in and out of Dynamics mode, we have to do some special things}
   If   IsDynamicModel and NOT ValueIsDynamic
   THEN InvalidateAllPCELEMENTS;  // Force Recomp of YPrims when we leave Dynamics mode

   IF NOT IsDynamicModel and ValueIsDynamic
   THEN Begin   // see if conditions right for going into dynamics

       IF ActiveCircuit[ActiveActor].IsSolved
       THEN  CalcInitialMachineStates   // set state variables for machines (loads and generators)
       ELSE Begin
           {Raise Error Message if not solved}
            DoSimpleMsg('Circuit must be solved in a non-dynamic mode before entering Dynamics or Fault study modes!' + CRLF +
                        'If you attempted to solve, then the solution has not yet converged.', 486);
            IF In_ReDirect Then Redirect_Abort := TRUE;  // Get outta here
            Result := FALSE;
       End;
   End;

end;

FUNCTION TSolutionObj.OK_for_Harmonics(const Value:Integer): Boolean;

 {When we go in and out of Harmonics mode, we have to do some special things}
begin

   Result := TRUE;

   If IsHarmonicModel and NOT ((Value=HARMONICMODE)or(Value=HARMONICMODET))
   THEN Begin
       InvalidateAllPCELEMENTS;  // Force Recomp of YPrims when we leave Harmonics mode
       Frequency := ActiveCircuit[ActiveActor].Fundamental;   // Resets everything to norm
   End;

   IF NOT IsHarmonicModel and ((Value=HARMONICMODE)or(Value=HARMONICMODET))
   THEN Begin   // see if conditions right for going into Harmonics

       IF (ActiveCircuit[ActiveActor].IsSolved) and (Frequency = ActiveCircuit[ActiveActor].Fundamental)
       THEN  Begin
           IF Not InitializeForHarmonics(ActiveActor)   // set state variables for machines (loads and generators) and sources
           THEN Begin
                Result := FALSE;
                IF In_ReDirect Then Redirect_Abort := TRUE;  // Get outta here
             End;
         End
       ELSE Begin
         
            DoSimpleMsg('Circuit must be solved in a fundamental frequency power flow or direct mode before entering Harmonics mode!', 487);
            IF In_ReDirect Then Redirect_Abort := TRUE;  // Get outta here
            Result := FALSE;
       End;
   End;

end;

procedure TSolutionObj.Set_Frequency(const Value: Double);
begin
      IF  FFrequency <> Value
      Then Begin
           FrequencyChanged := TRUE;  // Force Rebuild of all Y Primitives
           SystemYChanged := TRUE;  // Force rebuild of System Y
      End;

      FFrequency := Value;
      If ActiveCircuit[ActiveActor] <> Nil Then Harmonic := FFrequency / ActiveCircuit[ActiveActor].Fundamental;  // Make Sure Harmonic stays in synch
end;

procedure TSolutionObj.Increment_time;
begin
       With Dynavars
       Do Begin
            t := t+h;
            while t >= 3600.0
            do Begin
                  Inc(intHour);
                  t := t - 3600.0;
            End;
            Update_dblHour;
       End;
end;

procedure TSolutionObj.InitPropertyValues(ArrayOffset: Integer);
begin

     PropertyValue[1] := '';

     Inherited InitPropertyValues(NumPropsThisClass);

end;

procedure TSolutionObj.Set_Year(const Value: Integer);
begin
      If DIFilesAreOpen Then EnergyMeterClass[ActiveActor].CloseAllDIFiles;
      FYear := Value;
      DynaVars.intHour := 0;  {Change year, start over}
      Dynavars.t := 0.0;
      Update_dblHour;
      EnergyMeterClass[ActiveActor].ResetAll(ActiveActor);  // force any previous year data to complete
end;

procedure TSolutionObj.Set_Total_Time(const Value: Double);
begin
      Total_Time_Elapsed :=  Value;
end;

procedure TSolutionObj.SaveVoltages;

Var F:TextFile;
    Volts:Complex;
    i,j:integer;
    BusName:String;

begin

  Try

      Try
           AssignFile(F, CircuitName_[ActiveActor] + 'SavedVoltages.Txt');
           Rewrite(F);

           WITH ActiveCircuit[ActiveActor] DO
               FOR i := 1 to NumBuses
               DO Begin
                   BusName := BusList.Get(i);
                   For j := 1 to Buses^[i].NumNodesThisBus
                   DO Begin
                       Volts := NodeV^[Buses^[i].GetRef(j)];
                       Writeln(F, BusName, ', ', Buses^[i].GetNum(j):0, Format(', %-.7g, %-.7g',[Cabs(Volts), CDang(Volts)]));
                   End;
               End;

      Except
            On E:Exception Do Begin
             DoSimpleMsg('Error opening Saved Voltages File: '+E.message, 488);
             Exit;
            End;
      End;


  Finally

     CloseFile(F);
     GlobalResult := CircuitName_[ActiveActor] + 'SavedVoltages.Txt';

  End;

end;

{  *************  MAIN SOLVER CALL  ************************}

FUNCTION TSolutionObj.SolveSystem(V:pNodeVArray; actorID : Integer): Integer;

Var
  RetCode:Integer;
  iRes: LongWord;
  dRes: Double;

BEGIN

 {Note: NodeV[0] = 0 + j0 always.  Therefore, pass the address of the element 1 of the array.
 }
  Try
    // new function to log KLUSolve.DLL function calls; same information as stepping through in Delphi debugger
    // SetLogFile ('KLU_Log.txt', 1);
    RetCode := SolveSparseSet[ActorID](hY, @V^[1], @Currents^[1]);  // Solve for present InjCurr
    // new information functions
    GetFlops[ActorID](hY, @dRes);
    GetRGrowth[ActorID](hY, @dRes);
    GetRCond[ActorID](hY, @dRes);
    // GetCondEst (hY, @dRes); // this can be expensive
    GetSize[ActorID](hY, @iRes);
    GetNNZ[ActorID](hY, @iRes);
    GetSparseNNZ[ActorID](hY, @iRes);
    GetSingularCol[ActorID](hY, @iRes);
  Except
    On E:Exception Do Raise  EEsolv32Problem.Create('Error Solving System Y Matrix.  Sparse matrix solver reports numerical error: '
                   +E.Message);
  End;

   Result := RetCode;

END;

procedure TSolutionObj.Update_dblHour;
begin
     DynaVars.dblHour := DynaVars.intHour + dynavars.t/3600.0;
end;

procedure TSolutionObj.UpdateLoopTime;
begin

// Update Loop time is called from end of time step cleanup
// Timer is based on beginning of SolveSnap time

   QueryPerformanceCounter(LoopEndtime);
   Step_Time_Elapsed  := ((LoopEndtime-SolveStartTime)/CPU_Freq)*1000000;

end;

procedure TSolutionObj.UpdateVBus;

// Save present solution vector values to buses
Var
   i, j:Integer;
Begin
   WITH ActiveCircuit[ActiveActor] Do
    FOR i := 1 to NumBuses Do
     WITH Buses^[i] Do
       If Assigned(Vbus)
       Then FOR j := 1 to NumNodesThisBus Do  VBus^[j] := NodeV^[GetRef(j)];
End;

procedure TSolutionObj.RestoreNodeVfromVbus;
Var
   i, j:Integer;
Begin
   WITH ActiveCircuit[ActiveActor] Do
    FOR i := 1 to NumBuses Do
     WITH Buses^[i] Do
       If Assigned(Vbus)
       Then FOR j := 1 to NumNodesThisBus Do NodeV^[GetRef(j)]  := VBus^[j];

end;



FUNCTION TSolutionObj.SolveYDirect(ActorID : Integer): Integer;

{ Solves present Y matrix with no injection sources except voltage and current sources }

BEGIN

   Result := 0;

   ZeroInjCurr(ActorID);   // Side Effect: Allocates InjCurr
   GetSourceInjCurrents(ActorID);
   If IsDynamicModel Then GetPCInjCurr(ActorID);  // Need this in dynamics mode to pick up additional injections

   SolveSystem(NodeV, ActorID); // Solve with Zero injection current

END;

{*******************************************************************************
*             Used to create the OpenDSS Solver thread                         *
********************************************************************************
}

constructor TSolver.Create(Susp: Boolean; local_CPU: integer; ID : integer; CallBack: TInfoMessageCall);

var
  Parallel  : TParallel_Lib;
  Thpriority: String;
begin
  Inherited Create(Susp);
  FInfoProc       :=  CallBack;
  FreeOnTerminate := False;
  ActorID         :=  ID;
  Parallel.Set_Process_Priority(GetCurrentProcess(), REALTIME_PRIORITY_CLASS);
  Parallel.Set_Thread_Priority(handle,THREAD_PRIORITY_TIME_CRITICAL);
  Parallel.Set_Thread_affinity(handle,local_CPU);
end;

{*******************************************************************************
*             executes the selected solution algorithm                         *
********************************************************************************
}

procedure TSolver.Execute;
var
  ScriptEd  : TScriptEdit;
  begin
    with ActiveCircuit[ActorID].Solution do
    begin
      if ActorStatus[ActorID] = 1 then
      begin
        ActorStatus[ActorID] := 0;
        FMessage  :=  '1';
        if Not IsDLL then synchronize(CallCallBack);
//        InitProgressForm(ActorID); // initialize Progress Form;
           Case Dynavars.SolutionMode OF
               SNAPSHOT       : SolveSnap(ActorID);
               YEARLYMODE     : SolveYearly(ActorID);
               DAILYMODE      : SolveDaily(ActorID);
               DUTYCYCLE      : SolveDuty(ActorID);
               DYNAMICMODE    : SolveDynamic(ActorID);
               MONTECARLO1    : SolveMonte1(ActorID);
               MONTECARLO2    : SolveMonte2(ActorID);
               MONTECARLO3    : SolveMonte3(ActorID);
               PEAKDAY        : SolvePeakDay(ActorID);
               LOADDURATION1  : SolveLD1(ActorID);
               LOADDURATION2  : SolveLD2(ActorID);
               DIRECT         : SolveDirect(ActorID);
               MONTEFAULT     : SolveMonteFault(ActorID);  // Monte Carlo Fault Cases
               FAULTSTUDY     : SolveFaultStudy(ActorID);
               AUTOADDFLAG    : ActiveCircuit[ActorID].AutoAddObj.Solve(ActorID);
               HARMONICMODE   : SolveHarmonic(ActorID);
               GENERALTIME    : SolveGeneralTime(ActorID);
               HARMONICMODET  : SolveHarmonicT(ActorID);  //Declares the Hsequential-time harmonics
           Else
               DosimpleMsg('Unknown solution mode.', 481);
           End;
        QueryPerformanceCounter(GEndTime);
        Total_Solve_Time_Elapsed := ((GEndTime-GStartTime)/CPU_Freq)*1000000;
        Total_Time_Elapsed := Total_Time_Elapsed + Total_Solve_Time_Elapsed;
//        ProgressHide(ActorID);
        ActorStatus[ActorID]  :=  1;
        FMessage  :=  '1';
        if Not IsDLL then synchronize(CallCallBack);
      end;
    end;
  end;
procedure TSolver.CallCallBack;
  begin
    if Assigned(FInfoProc) then  FInfoProc(FMessage);
  end;

initialization

    {$IFDEF debugtrace}
    Assignfile(Fdebug, 'Debugtrace.csv');
    Rewrite(Fdebug);

    CloseFile(Fdebug);
   {$ENDIF}

End.

