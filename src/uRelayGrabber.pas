unit uRelayGrabber;

interface

uses
  System.Types,
  System.Classes,
  System.SysUtils,
  System.Generics.Collections,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.JSON,
  IdTCPClient,
  IdGlobal;

type

  TTorRelay = class
  public
    Fingerprint: string;
    Nickname: string;
    Address: string;
    ORPort: Integer;
    DirPort: Integer;
    CountryCode: string;
    IsAlive: Boolean;
    Latency: Integer;
  end;

  TScanProgressEvent = procedure(Sender: TObject; Current, Total: Integer;
    const RelayInfo: string) of object;
  TScanMessageEvent = procedure(Sender: TObject; const Msg: string;
    Success: Boolean) of object;
  TScanCompleteEvent = procedure(Sender: TObject;
    Results: TObjectList<TTorRelay>) of object;

  TRelayGrabber = class(TThread)
  private
    FRelays: TObjectList<TTorRelay>;
    FResults: TObjectList<TTorRelay>;
    FMaxRelays: Integer;
    FCountryFilter: string;
    FOnStarting: TNotifyEvent;
    FOnProgress: TScanProgressEvent;
    FOnComplete: TScanCompleteEvent;
    FOnMessage: TScanMessageEvent;
    FErrorMessage: string;
    FCurrentSource: string;
    // Массив резервных URL (в порядке приоритета)
    class var FDataSourceURLs: TArray<string>;
    class var FTimeoutMS: Integer;
    class constructor Create;
    function TryFetchFromURL(const AURL: string): TJSONObject;
    function TryFetchFromResource(): TJSONObject;
    procedure FetchRelaysFromAnySource;
    procedure DoProgress(Current, Total: Integer; const Info: string);
    procedure DoMessage(const Msg: string; Success: Boolean = True);
    procedure DoStarting;
    procedure DoComplete;
    procedure HandleJSONData(JSONData: TJSONObject);
  protected
    procedure Execute; override;
  public
    constructor Create(const ACountryFilter: string = ''; AMaxRelays: Integer = 100;
      ATimeoutMS: Integer = 5000);
    destructor Destroy; override;
    class procedure AddDataSource(const AURL: string);
    class function CheckRelayPort(const AAddress: string; APort: Integer): Boolean;
    class function CheckTorRelay(const AAddress: string; APort: Integer;
      var AError: string): Boolean;
    property Terminated;
    property OnStarting: TNotifyEvent read FOnStarting write FOnStarting;
    property OnProgress: TScanProgressEvent read FOnProgress write FOnProgress;
    property OnComplete: TScanCompleteEvent read FOnComplete write FOnComplete;
    property OnMessage: TScanMessageEvent read FOnMessage write FOnMessage;
    property ErrorMessage: string read FErrorMessage;
    property Results: TObjectList<TTorRelay> read FResults;
  end;

implementation

{$R *.res}

uses
  System.NetEncoding,
  System.StrUtils,
  System.Math,
  IdStack,
  IdExceptionCore;

procedure ShuffleJSONArray(JSONArray: TJSONArray);
var
  i, randomIndex: Integer;
  tempList: TList<TJSONValue>;
begin
  if not Assigned(JSONArray) or (JSONArray.Count <= 1) then
    Exit;

  tempList := TList<TJSONValue>.Create;
  try
    // Извлекаем все элементы из массива
    while JSONArray.Count > 0 do
    begin
      tempList.Add(JSONArray.Remove(0));
    end;

    // Перемешиваем, извлекая случайные элементы
    while tempList.Count > 0 do
    begin
      randomIndex := Random(tempList.Count);
      // Используем AddElement, так как передаем существующий объект
      JSONArray.AddElement(tempList[randomIndex]);
      tempList.Delete(randomIndex);
    end;
  finally
    tempList.Free;
  end;
end;


class constructor TRelayGrabber.Create;
begin
  FTimeoutMS := 5000;
end;

constructor TRelayGrabber.Create(const ACountryFilter: string; AMaxRelays,
  ATimeoutMS: Integer);
begin
  inherited Create(True);
  FRelays := TObjectList<TTorRelay>.Create(True);
  FResults := TObjectList<TTorRelay>.Create(True);
  FCountryFilter := UpperCase(ACountryFilter);
  FMaxRelays := AMaxRelays;
  FTimeoutMS := ATimeoutMS;
  FErrorMessage := '';
  FCurrentSource := '';

  // Инициализируем стандартные источники, если еще не инициализированы
  if Length(FDataSourceURLs) = 0 then
  begin
    // Основной URL Tor Project
    FDataSourceURLs := [
      'https://raw.githubusercontent.com/ValdikSS/tor-onionoo-mirror/master/details-running-relays-fingerprint-address-only.json',
      'https://bitbucket.org/ValdikSS/tor-onionoo-mirror/raw/master/details-running-relays-fingerprint-address-only.json'
    ];
  end;
end;

destructor TRelayGrabber.Destroy;
begin
  FRelays.Free;
  FResults.Free;
  inherited;
end;

class procedure TRelayGrabber.AddDataSource(const AURL: string);
begin
  FDataSourceURLs := FDataSourceURLs + [AURL];
end;

procedure TRelayGrabber.Execute;
var
  I, n, m, AliveCount: Integer;
  Relay: TTorRelay;
  msg: string;
begin
  try
    // 1. Получение списка реле
    FetchRelaysFromAnySource;
    if Terminated then
      Exit;

    if FRelays.Count = 0 then
    begin
      FErrorMessage := 'No relays loaded from any source';
      DoComplete;
      Exit;
    end;

    AliveCount := 0;
    n := 0;
    m := FRelays.Count;
    Synchronize(DoStarting);
    DoMessage(Format('Checking %d relays...', [FRelays.Count]));
    // 2. Проверка доступности каждого реле
    for I := FRelays.Count - 1 downto 0 do
    begin
      if Terminated then
        Break;
      Inc(n);
      Relay := FRelays[I];
      DoProgress(n, m, Format('Checking %s (%s:%d) %s...',
        [Relay.Fingerprint, Relay.Address, Relay.ORPort, Relay.CountryCode]));

      msg := 'Relay port error';
      // Проверяем ORPort (основной порт Tor)
      Relay.IsAlive := CheckRelayPort(Relay.Address, Relay.ORPort);
      if Relay.IsAlive then
        Relay.IsAlive := CheckTorRelay(Relay.Address, Relay.ORPort, msg);

      if Relay.IsAlive then
      begin
        Inc(AliveCount);
        Relay.Latency := 0; // Здесь можно добавить реальный расчет времени отклика
        FResults.Add(Relay);
        FRelays.Extract(Relay); // Чтобы не освободился в деструкторе FRelays
      end
      else
      begin
        DoMessage(msg, False);
      end;
    end;

    DoMessage(Format('Scan complete. Found %d active relays.', [AliveCount]));
  except
    on E: Exception do
    begin
      FErrorMessage := E.Message;
      DoMessage('Error: ' + E.Message, False);
    end;
  end;

  Synchronize(DoComplete);
end;

procedure TRelayGrabber.FetchRelaysFromAnySource;
var
  I: Integer;
  JSONData: TJSONObject;
begin
  JSONData := nil;

  // Пробуем все источники по очереди
  for I := 0 to High(FDataSourceURLs) do
  begin
    if Terminated then
      Break;

    JSONData := TryFetchFromURL(FDataSourceURLs[I]);
    if Assigned(JSONData) then
      Break;

    // Небольшая пауза между попытками
    Sleep(1000);
  end;

  if not Assigned(JSONData) then
  begin
    // достаём из ресурса
    JSONData := TryFetchFromResource();
  end;

  if Assigned(JSONData) then
  try
    HandleJSONData(JSONData);
  finally
    JSONData.Free;
  end
  else
    raise Exception.Create('Failed to fetch data from all available sources');
end;

procedure TRelayGrabber.HandleJSONData(JSONData: TJSONObject);
var
  RelaysArray: TJSONArray;
  I, RelayCount: Integer;
  RelayObj: TJSONObject;
  Relay: TTorRelay;
  CountryValue, AddrValue: TJSONValue;
  OrAddresses, CountryCode: string;
  AddrParts: TArray<string>;
  IsValidCountry, IsValidAddress: Boolean;
  RootValue: TJSONValue;
begin
  // Получаем корневое значение - это может быть объект или массив
  RootValue := JSONData;

  // Сбросим указатель на массив
  RelaysArray := nil;

  // Вариант 1: JSONData уже содержит массив relays в поле "relays"
  CountryValue := JSONData.GetValue('relays');
  if (CountryValue <> nil) and (CountryValue is TJSONArray) then
  begin
    RelaysArray := TJSONArray(CountryValue);
  end
  else
  begin
    // Вариант 2: JSONData это сам массив (без обертки в объект)
    // НО: JSONData объявлен как TJSONObject, поэтому такой вариант невозможен
    // Значит, если нет поля 'relays', то это ошибка формата
    DoMessage('Invalid JSON format: no "relays" array found', False);
    Exit;
  end;

  if RelaysArray = nil then
  begin
    DoMessage('No relays data found in JSON', False);
    Exit;
  end;

  ShuffleJSONArray(RelaysArray);

  RelayCount := Min(RelaysArray.Count, FMaxRelays);
  DoMessage(Format('Parsing %d relays from JSON...', [RelayCount]));

  for I := 0 to RelayCount - 1 do
  begin
    if Terminated then Break;

    if not (RelaysArray.Items[I] is TJSONObject) then
    begin
      DoMessage(Format('Warning: Item %d is not a JSON object', [I]), False);
      Continue;
    end;

    RelayObj := TJSONObject(RelaysArray.Items[I]);

    Relay := TTorRelay.Create;
    try
      // 1. Парсим fingerprint (всегда строка)
      CountryValue := RelayObj.GetValue('fingerprint');
      if (CountryValue <> nil) and (CountryValue is TJSONString) then
        Relay.Fingerprint := TJSONString(CountryValue).Value
      else
        Relay.Fingerprint := 'unknown';

      // 2. Парсим nickname
      CountryValue := RelayObj.GetValue('nickname');
      if (CountryValue <> nil) and (CountryValue is TJSONString) then
        Relay.Nickname := TJSONString(CountryValue).Value
      else
        Relay.Nickname := 'unnamed';

      // 3. ПАРСИМ СТРАНУ
      CountryCode := '??';
      CountryValue := RelayObj.GetValue('country');

      if CountryValue <> nil then
      begin
        // Вариант 1: строка (например, "US")
        if CountryValue is TJSONString then
        begin
          CountryCode := TJSONString(CountryValue).Value;
          IsValidCountry := True;
        end
        // Вариант 2: массив строк (например, ["US", "DE"])
        else if CountryValue is TJSONArray then
        begin
          if TJSONArray(CountryValue).Count > 0 then
          begin
            AddrValue := TJSONArray(CountryValue).Items[0];
            if AddrValue is TJSONString then
              CountryCode := TJSONString(AddrValue).Value;
          end;
          IsValidCountry := True;
        end
        // Вариант 3: объект или другой тип
        else if CountryValue is TJSONObject then
        begin
          DoMessage(Format('Warning: Country is object for relay %s', [Relay.Nickname]), False);
          IsValidCountry := False;
        end
        else
        begin
          // Пробуем получить значение как строку (для чисел и булевых)
          CountryCode := CountryValue.Value;
          IsValidCountry := True;
        end;
      end
      else
        IsValidCountry := False;

      Relay.CountryCode := CountryCode;

      // 4. Парсим порты
      CountryValue := RelayObj.GetValue('or_port');
      if CountryValue <> nil then
      begin
        if CountryValue is TJSONNumber then
          Relay.ORPort := StrToIntDef(TJSONNumber(CountryValue).Value, 443)
        else if CountryValue is TJSONString then
          Relay.ORPort := StrToIntDef(TJSONString(CountryValue).Value, 443)
        else
          Relay.ORPort := 443;
      end
      else
        Relay.ORPort := 443;

      CountryValue := RelayObj.GetValue('dir_port');
      if CountryValue <> nil then
      begin
        if CountryValue is TJSONNumber then
          Relay.DirPort := StrToIntDef(TJSONNumber(CountryValue).Value, 80)
        else if CountryValue is TJSONString then
          Relay.DirPort := StrToIntDef(TJSONString(CountryValue).Value, 80)
        else
          Relay.DirPort := 80;
      end
      else
        Relay.DirPort := 80;

      // 5. Парсим адреса
      OrAddresses := '';
      IsValidAddress := False;

      // Сначала пробуем 'or_addresses', затем 'a'
      CountryValue := RelayObj.GetValue('or_addresses');
      if CountryValue = nil then
        CountryValue := RelayObj.GetValue('a');

      if CountryValue <> nil then
      begin
        // Вариант 1: строка с адресом "IP:PORT" или "IP"
        if CountryValue is TJSONString then
        begin
          OrAddresses := TJSONString(CountryValue).Value;
          IsValidAddress := True;
        end
        // Вариант 2: массив адресов ["IP1:PORT", "IP2:PORT"]
        else if CountryValue is TJSONArray then
        begin
          if TJSONArray(CountryValue).Count > 0 then
          begin
            AddrValue := TJSONArray(CountryValue).Items[0];
            if AddrValue is TJSONString then
            begin
              OrAddresses := TJSONString(AddrValue).Value;
              IsValidAddress := True;
            end;
          end;
        end;
      end;

      // Разбираем полученный адрес
      if IsValidAddress and (OrAddresses <> '') then
      begin
        AddrParts := OrAddresses.Split([':']);
        Relay.Address := AddrParts[0];
        if Length(AddrParts) > 1 then
          Relay.ORPort := StrToIntDef(AddrParts[1], Relay.ORPort);
      end
      else
      begin
        Relay.Address := '';
        DoMessage(Format('Warning: No valid address for relay %s', [Relay.Nickname]), False);
      end;

      // 6. Применяем фильтр по стране и добавляем реле
      if ((FCountryFilter = '') or (UpperCase(Relay.CountryCode) = FCountryFilter)) and
         (Relay.Address <> '') then
      begin
        FRelays.Add(Relay);

        // Логируем каждое 10-е реле
        if (FRelays.Count mod 10 = 0) then
          DoMessage(Format('Added %d relays...', [FRelays.Count]));
      end
      else
      begin
        Relay.Free;
      end;

    except
      on E: Exception do
      begin
        DoMessage(Format('Error parsing relay %d: %s', [I, E.Message]), False);
        Relay.Free;
      end;
    end;
  end;

  DoMessage(Format('Successfully parsed %d relays', [FRelays.Count]));
end;


function TRelayGrabber.TryFetchFromResource: TJSONObject;
var
  rs: TResourceStream;
  s: AnsiString;
  JsonValue: TJSONValue;
begin
  rs := TResourceStream.Create(hInstance, 'JSONDATA', RT_RCDATA);
  try
    SetLength(s, rs.Size);
    rs.Read(PAnsiChar(s)^, rs.Size);
    JsonValue := TJSONObject.ParseJSONValue(string(s));
    if Assigned(JsonValue) and (JsonValue is TJSONObject) then
      Result := TJSONObject(JsonValue)
    else
    begin
      FreeAndNil(JsonValue);
      Result := nil;
    end;
  finally
    rs.Free;
  end;
end;

function TRelayGrabber.TryFetchFromURL(const AURL: string): TJSONObject;
var
  HTTPClient: THTTPClient;
  Response: IHTTPResponse;
begin
  Result := nil;
  DoMessage('Trying to fetch from: ' + Copy(AURL, 1, 80) + '...');

  HTTPClient := THTTPClient.Create;
  try
    HTTPClient.UserAgent := 'TorRelayGrabber/1.0 (Windows NT 10.0; Win64; x64)';
    HTTPClient.ConnectionTimeout := FTimeoutMS;
    HTTPClient.ResponseTimeout := FTimeoutMS * 2;

    // Дополнительные настройки для избежания ошибок соединения
    HTTPClient.Accept := 'application/json';
    HTTPClient.ContentType := 'application/json';

    Response := HTTPClient.Get(AURL);

    if Response.StatusCode = 200 then
    begin
      DoMessage('Successfully fetched data from source', True);
      Result := TJSONObject.ParseJSONValue(Response.ContentAsString) as TJSONObject;
      FCurrentSource := AURL;
    end
    else
    begin
      DoMessage(Format('HTTP error %d from source', [Response.StatusCode]), False);
    end;
  except
    on E: ENetHTTPClientException do
    begin
      DoMessage('Network error: ' + E.Message, False);
      // Продолжаем пробовать другие источники
    end;
    on E: Exception do
    begin
      DoMessage('Error: ' + E.Message, False);
    end;
  end;
end;

class function TRelayGrabber.CheckRelayPort(const AAddress: string; APort: Integer): Boolean;
var
  TCPClient: TIdTCPClient;
begin
  Result := False;
  TCPClient := TIdTCPClient.Create(nil);
  try
    TCPClient.ConnectTimeout := FTimeoutMS;
    TCPClient.ReadTimeout := 2000;

    try
      TCPClient.Host := AAddress;
      TCPClient.Port := APort;
      TCPClient.Connect;
      Result := TCPClient.Connected;
      TCPClient.Disconnect;
    except
      Result := False; // Любая ошибка = порт недоступен
    end;
  finally
    TCPClient.Free;
  end;
end;

class function TRelayGrabber.CheckTorRelay(const AAddress: string; APort: Integer;
  var AError: string): Boolean;
var
  TCPClient: TIdTCPClient;
  StartTime: Cardinal;
begin
  Result := False;
  AError := '';
  TCPClient := TIdTCPClient.Create(nil);
  StartTime := GetTickCount;

  try
    TCPClient.ConnectTimeout := FTimeoutMS;
    TCPClient.ReadTimeout := 2000; // Для быстрой проверки
    TCPClient.Host := AAddress;
    TCPClient.Port := APort;

    try
      // 1. Основная проверка - TCP подключение
      TCPClient.Connect;

      Result := TCPClient.Connected;

      if not Result then
      begin
        AError := 'TCP connection failed';
        Exit;
      end;

    except
      on E: EIdSocketError do
        AError := Format('Socket error %d', [E.LastError]);
      on E: EIdConnectTimeout do
        AError := 'Connection timeout';
      on E: Exception do
        AError := E.Message;
    end;

  finally
    if TCPClient.Connected then
      TCPClient.Disconnect;
    TCPClient.Free;
  end;

  // Финальная гарантия: если Result=True, но AError пуст
  if AError = '' then
  begin
    AError := IfThen(Result, 'Connected successfully', 'Checking error');
  end;
end;

procedure TRelayGrabber.DoProgress(Current, Total: Integer; const Info: string);
begin
  if Assigned(FOnProgress) then
    Synchronize(
      procedure
      begin
        FOnProgress(Self, Current, Total, Info);
      end
    );
end;

procedure TRelayGrabber.DoStarting;
begin
  if Assigned(FOnStarting) then
    FOnStarting(Self);
end;

procedure TRelayGrabber.DoComplete;
begin
  if Assigned(FOnComplete) then
    FOnComplete(Self, FResults);
end;

procedure TRelayGrabber.DoMessage(const Msg: string; Success: Boolean);
begin
  if Assigned(FOnMessage) then
  Synchronize(
    procedure
    begin
      FOnMessage(Self, Msg, Success);
    end
    );
end;

end.
