unit RetryTactic;

interface

uses
{Delphi}
  System.SysUtils
{Project}
  , Logger.LoggerIntf
  ;

type
  TRetry = class
  strict private
    FMaxAttempts: Integer;
    FDelayBetweenAttemptsMs: Integer;
    FUseBackoff: Boolean;
    FBaseDelay: Integer;
    FLogger: ILogger;
  public
    constructor Create(ALogger: ILogger);
    destructor Destroy; override;

    function MaxAttempts(ACount: Integer): TRetry;
    function DelayBetweenAttempts(AMilliseconds: Integer): TRetry;
    function UseExponentialBackoff(ABaseDelay: Integer): TRetry;

    function TryExecute<T>(const AFunc: TFunc<T>; const AValidator: TFunc<T, Boolean>; out AValue: T): Boolean;

    class function New(ALogger: ILogger): TRetry; static;
  end;

implementation

{*
  Usage:
  procedure TForm4.BitBtn1Click(Sender: TObject);
  var
    _Result: String;
    _Success: Boolean;
  begin
    _Success := TRetry.New(TConsoleLogger.Create)
      .MaxAttempts(5)
      //.DelayBetweenAttempts(1000)
      .UseExponentialBackoff(250)
      .TryExecute<String>(
      function: String
      begin
        if Random < 0.7 then
          raise Exception.Create('Random failure');
        Result := 'OK';
      end,
      function(AValue: String): Boolean
      begin
        Result := AValue = 'OK';
      end,
      _Result);

    if _Success then
      ShowMessage('Success: ' + _Result)
    else
      ShowMessage('Retry failed.');
  end;
*}

constructor TRetry.Create(ALogger: ILogger);
begin
  inherited Create;
  FMaxAttempts := 3;
  FDelayBetweenAttemptsMs := 0;
  FLogger := ALogger;
  if not Assigned(FLogger) then
    raise EArgumentException.Create('Logger is not provided');
end;

destructor TRetry.Destroy;
begin
  FLogger := nil;
  inherited;
end;

function TRetry.MaxAttempts(ACount: Integer): TRetry;
begin
  FMaxAttempts := ACount;
  Result := Self;
end;

function TRetry.DelayBetweenAttempts(AMilliseconds: Integer): TRetry;
begin
  FUseBackoff := False;
  FDelayBetweenAttemptsMs := AMilliseconds;
  Result := Self;
end;

function TRetry.UseExponentialBackoff(ABaseDelay: Integer): TRetry;
begin
  FUseBackoff := True;
  FBaseDelay := ABaseDelay;
  Result := Self;
end;

function TRetry.TryExecute<T>(const AFunc: TFunc<T>; const AValidator: TFunc<T, Boolean>; out AValue: T): Boolean;
var
  _Attempt: Integer;
  _TempResult: T;
begin
  Result := False;

  for _Attempt := 1 to FMaxAttempts do
  begin
    try
      if Assigned(FLogger) then
        FLogger.LogMessage(Format('Attempt %d of %d', [_Attempt, FMaxAttempts]));

      _TempResult := AFunc();

      if AValidator(_TempResult) then
      begin
        AValue := _TempResult;
        Result := True;
        Exit;
      end;

      if Assigned(FLogger) then
        FLogger.LogMessage('Validator rejected the result.');

    except
      on E: Exception do
        if Assigned(FLogger) then
          FLogger.LogMessage(Format('Exception on attempt %d: %s', [_Attempt, E.Message]));
    end;

    if _Attempt < FMaxAttempts then
    begin
      var _Delay := FDelayBetweenAttemptsMs;

      if FUseBackoff then
        _Delay := FBaseDelay * (1 shl (_Attempt - 1)); // 1 << (attempt - 1)

      FLogger.LogMessage(Format('Sleeping %d ms before next attempt', [_Delay]));
      Sleep(_Delay);
    end;
  end;
end;

class function TRetry.New(ALogger: ILogger): TRetry;
begin
  Result := TRetry.Create(ALogger);
end;

end.

