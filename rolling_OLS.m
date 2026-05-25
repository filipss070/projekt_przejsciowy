disp('Skanowanie folderów w poszukiwaniu plików CSV...');

% 1. Odczytanie listy wszystkich plików w folderach
folder_btc = 'dane/BTC/';
folder_eth = 'dane/ETH/';
pliki_btc = dir(fullfile(folder_btc, '*.csv'));
pliki_eth = dir(fullfile(folder_eth, '*.csv'));

% Sprawdzenie, czy foldery nie są puste
if isempty(pliki_btc) || isempty(pliki_eth)
    error('Nie znaleziono plików .csv w podanych folderach!');
end

disp(['Znaleziono plików BTC: ', num2str(length(pliki_btc)), ' | ETH: ', num2str(length(pliki_eth))]);

% Opcje importu (bez nagłówków)
opts = detectImportOptions(fullfile(pliki_btc(1).folder, pliki_btc(1).name), 'NumHeaderLines', 0);
opts.VariableNamingRule = 'preserve';

% 2. Prealokacja pamięci komórkowej (KRYTYCZNE DLA WYDAJNOŚCI RAM)
dane_komorki_btc = cell(length(pliki_btc), 1);
dane_komorki_eth = cell(length(pliki_eth), 1);

disp('Wczytywanie do pamięci RAM...');
% Pętla ładująca BTC
for i = 1:length(pliki_btc)
    sciezka = fullfile(pliki_btc(i).folder, pliki_btc(i).name);
    raw_b = readtable(sciezka, opts);
    dane_komorki_btc{i} = prepare_binance_data(raw_b, 'BTC');
end

% Pętla ładująca ETH
for i = 1:length(pliki_eth)
    sciezka = fullfile(pliki_eth(i).folder, pliki_eth(i).name);
    raw_e = readtable(sciezka, opts);
    dane_komorki_eth{i} = prepare_binance_data(raw_e, 'ETH');
end

% 3. Błyskawiczne złączenie wszystkich plików w jedną wielką tabelę
disp('Sklejanie danych z wielu lat w jedną oś czasu...');
full_btc = vertcat(dane_komorki_btc{:});
full_eth = vertcat(dane_komorki_eth{:});

% 4. ZABEZPIECZENIE: Sortujemy po czasie, żeby naprawić kolejność, jeśli pliki wczytały się alfabetycznie zamiast chronologicznie
full_btc = sortrows(full_btc);
full_eth = sortrows(full_eth);

% --- KROK 3: Synchronizacja Całości ---
disp('Synchronizacja kwotowań na giełdzie...');
quarterly_data = synchronize(full_btc, full_eth, 'intersection');

disp(['Gotowe! Pełna liczba próbek w systemie: ', num2str(height(quarterly_data))]);

function tt_out = prepare_binance_data(raw_table, label)
    timestamps = raw_table.(1); 
    close_prices = raw_table.(5);
    dates = datetime(timestamps/1000000, 'ConvertFrom', 'posixtime');
    col_name = strcat('Close_', label);
    tt_out = timetable(dates, close_prices, 'VariableNames', {col_name});
end


% Wyciąganie wektorów do zmiennych
y = quarterly_data.Close_ETH; % Twoje y (ETH)
x = quarterly_data.Close_BTC; % Twoje x (BTC) do macierzy H
y = y(1:5:end);
x = x(1:5:end);
x_log = log(x);
y_log = log(y);
time_axis = quarterly_data.Properties.RowTimes; % Oś czasu do wykresów
time_axis = time_axis(1:5:end);


% A = beta*B + alfa 
aktywo_B = y_log;
aktywo_A = x_log;
aktywo_B1 = y;
aktywo_A1 = x;

okno = 288*7;
h_adf = zeros(1,length(x));
beta_alfa1 = zeros(1,2);
beta_alfa2 = zeros(1,2);
spread1 = zeros(1, length(x));
spread2 = zeros(1, length(x));
z_score1 = zeros(1, length(x));
z_score2 = zeros(1, length(x));

eth_obstawione = 0;
cena_eth_w_momencie_obstawiania = 0;
cena_btc_w_momencie_obstawiania = 0;
btc_obstawione = 0;
zscore2 = false;
zscoreneg2 = false;
kapital_history = zeros(1, length(x));
min_profit = 0.004;
ilosc_tranzakcji = 0;
kapital = 10000;
tranzakcja = false;
beta_historyOLS1 = zeros(1,length(x));
beta_historyOLS2 = zeros(1,length(x));

for i = okno:length(x)
    beta_alfa1 = polyfit(aktywo_B(i-okno+1:i),aktywo_A(i-okno+1:i),1);
    beta_historyOLS1(i) = beta_alfa1(1);
    spread1(i) = aktywo_A(i) - aktywo_B(i)*beta_alfa1(1) - beta_alfa1(2);
    spread_aktualne_okno1 = aktywo_A(i-okno+1:i) - aktywo_B(i-okno+1:i)*beta_alfa1(1) - beta_alfa1(2);
    wariancja_spreadu1 = var(spread_aktualne_okno1);
    z_score1(i) = (spread1(i)-mean(spread_aktualne_okno1))/sqrt(wariancja_spreadu1);

    beta_alfa2 = polyfit(aktywo_A(i-okno+1:i),aktywo_B(i-okno+1:i),1);
    beta_historyOLS2(i) = beta_alfa2(1);
    spread2(i) = aktywo_B(i) - aktywo_A(i)*beta_alfa2(1) - beta_alfa2(2);
    spread_aktualne_okno2 = aktywo_B(i-okno+1:i) - aktywo_A(i-okno+1:i)*beta_alfa2(1) - beta_alfa2(2);
    wariancja_spreadu2 = var(spread_aktualne_okno2);
    z_score2(i) = (spread2(i)-mean(spread_aktualne_okno2))/sqrt(wariancja_spreadu2);
    %{
    if not(mod(i,5))
        h_adf(i-4:i) = egcitest([aktywo_A(i-288*7:i), aktywo_B(i-288*7:i)]);
    end
    %}
    %{
    if tranzakcja == false && h_adf(i) 
        
        if z_score(i) > 0.05% && z_score(i) < -0.05  % sprawdzenie czy wyniki kalmanów są mniej więcej takie same % && abs(spread_history(i))/y(i) > min_profit
            [ilosc_eth, ilosc_btc] = CalculatePositionSize(kapital, aktywo_A1(i), aktywo_B1(i), beta_history(i));
            tranzakcja = true;
            eth_obstawione = aktywo_A1(i)*ilosc_eth;
            btc_obstawione = aktywo_B1(i)*ilosc_btc;
            cena_eth_w_momencie_obstawiania = aktywo_A1(i);
            cena_btc_w_momencie_obstawiania = aktywo_B1(i);
            zscore2 = true;
        elseif z_score(i) < -0.05% && z_score(i) > 0.05 %&& abs(spread_history(i))/y(i) > min_profit
            [ilosc_eth, ilosc_btc] = CalculatePositionSize(kapital, aktywo_A1(i), aktywo_B1(i), beta_history(i));
            tranzakcja = true;
            eth_obstawione = aktywo_A1(i)*ilosc_eth;
            btc_obstawione = aktywo_B1(i)*ilosc_btc;
            cena_eth_w_momencie_obstawiania = aktywo_A1(i);
            cena_btc_w_momencie_obstawiania = aktywo_B1(i);
            zscoreneg2 = true;
        end
    else
        if zscore2 == true
            if z_score(i) < 0 %&& (cena_eth_w_momencie_obstawiania-y(i))*eth_obstawione/cena_eth_w_momencie_obstawiania - (cena_btc_w_momencie_obstawiania-x(i))*btc_obstawione/cena_btc_w_momencie_obstawiania - 2*eth_obstawione*0.0005 - 2*btc_obstawione*0.0005 > 0
                zscore2 = false;
                tranzakcja = false;
                kapital = kapital + (cena_eth_w_momencie_obstawiania-aktywo_A1(i))*eth_obstawione/cena_eth_w_momencie_obstawiania - (cena_btc_w_momencie_obstawiania-aktywo_B1(i))*btc_obstawione/cena_btc_w_momencie_obstawiania;% - 2*eth_obstawione*0.0005 - 2*btc_obstawione*0.0005; %prowizja
                ilosc_tranzakcji = ilosc_tranzakcji + 1;
            end
        elseif zscoreneg2 == true
            if z_score(i) > 0 %&& (y(i)-cena_eth_w_momencie_obstawiania)*eth_obstawione/cena_eth_w_momencie_obstawiania - (x(i)-cena_btc_w_momencie_obstawiania)*btc_obstawione/cena_btc_w_momencie_obstawiania - 2*eth_obstawione*0.0005 - 2*btc_obstawione*0.0005 > 0
                zscoreneg2 = false;
                tranzakcja = false;
                kapital = kapital + (aktywo_A1(i)-cena_eth_w_momencie_obstawiania)*eth_obstawione/cena_eth_w_momencie_obstawiania - (aktywo_B1(i)-cena_btc_w_momencie_obstawiania)*btc_obstawione/cena_btc_w_momencie_obstawiania;% - 2*eth_obstawione*0.0005 - 2*btc_obstawione*0.0005; %prowizja
                ilosc_tranzakcji = ilosc_tranzakcji + 1;
            end
        end
    end
    kapital_history(i) = kapital;
    %}
    if mod(i,1000) == 0
        fprintf('\rAktualna wartość: %d', i);
    end
end

function [qty_eth, qty_btc] = CalculatePositionSize(capital_usd, price_eth, price_btc, beta)

    allocation_eth = capital_usd / (1 + beta); 
    allocation_btc = capital_usd - allocation_eth;
    
    qty_eth = allocation_eth / price_eth;
    qty_btc = allocation_btc / price_btc; 
    
end



