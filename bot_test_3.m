% --- KROK 2: Automatyczne wczytywanie wieloletnich danych ---
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
y_log = log(y);
x = x(1:5:end);
x_log = log(x);
time_axis = quarterly_data.Properties.RowTimes; % Oś czasu do wykresów
time_axis = time_axis(1:5:end);

subplot(2,1,1); plot(time_axis, y, 'b');
subplot(2,1,2);plot(time_axis, x, 'g');


beta_history = zeros(1, length(x));
alpha_history = zeros(1, length(x));
y_pred_history = zeros(1, length(x));
spread_history = zeros(1, length(x));
z_score_history = zeros(1, length(x));
R_history = zeros(1, length(x));


eth_obstawione = 0;
cena_eth_w_momencie_obstawiania = 0;
cena_btc_w_momencie_obstawiania = 0;
btc_obstawione = 0;
zscore2 = false;
zscoreneg2 = false;
kapital_history = zeros(1, length(x));
min_profit = 0.004;
ilosc_tranzakcji = 0;
kapital = 1500;
tranzakcja = false;

clear KalmanSlidingWindow123;

for i = 1:length(x)
    [beta_history(i), alpha_history(i), z_score_history(i), R_history(i), spread_history(i), y_pred_history(i)] = KalmanSlidingWindow123(y_log(i),x_log(i));
    
    if tranzakcja == false && i > 100 % 100 próbek na ustawienie się macierzy P
        
        if z_score_history(i) > 0.15 %&& abs(spread_history(i))/y(i) > min_profit
            [ilosc_eth, ilosc_btc] = CalculatePositionSize(kapital, y(i), x(i), beta_history(i));
            tranzakcja = true;
            eth_obstawione = y(i)*ilosc_eth;
            btc_obstawione = x(i)*ilosc_btc;
            cena_eth_w_momencie_obstawiania = y(i);
            cena_btc_w_momencie_obstawiania = x(i);
            zscore2 = true;
        elseif z_score_history(i) < -0.15 %&& abs(spread_history(i))/y(i) > min_profit
            [ilosc_eth, ilosc_btc] = CalculatePositionSize(kapital, y(i), x(i), beta_history(i));
            tranzakcja = true;
            eth_obstawione = y(i)*ilosc_eth;
            btc_obstawione = x(i)*ilosc_btc;
            cena_eth_w_momencie_obstawiania = y(i);
            cena_btc_w_momencie_obstawiania = x(i);
            zscoreneg2 = true;
        end
    else
        if zscore2 == true
            if z_score_history(i) < 0.01 %&& (cena_eth_w_momencie_obstawiania-y(i))*eth_obstawione/cena_eth_w_momencie_obstawiania - (cena_btc_w_momencie_obstawiania-x(i))*btc_obstawione/cena_btc_w_momencie_obstawiania - 2*eth_obstawione*0.0005 - 2*btc_obstawione*0.0005 > 0
                zscore2 = false;
                tranzakcja = false;
                kapital = kapital + (cena_eth_w_momencie_obstawiania-y(i))*eth_obstawione/cena_eth_w_momencie_obstawiania - (cena_btc_w_momencie_obstawiania-x(i))*btc_obstawione/cena_btc_w_momencie_obstawiania;% - 2*eth_obstawione*0.0005 - 2*btc_obstawione*0.0005; %prowizja
                ilosc_tranzakcji = ilosc_tranzakcji + 1;
            end
        elseif zscoreneg2 == true
            if z_score_history(i) > -0.01 %&& (y(i)-cena_eth_w_momencie_obstawiania)*eth_obstawione/cena_eth_w_momencie_obstawiania - (x(i)-cena_btc_w_momencie_obstawiania)*btc_obstawione/cena_btc_w_momencie_obstawiania - 2*eth_obstawione*0.0005 - 2*btc_obstawione*0.0005 > 0
                zscoreneg2 = false;
                tranzakcja = false;
                kapital = kapital + (y(i)-cena_eth_w_momencie_obstawiania)*eth_obstawione/cena_eth_w_momencie_obstawiania - (x(i)-cena_btc_w_momencie_obstawiania)*btc_obstawione/cena_btc_w_momencie_obstawiania;% - 2*eth_obstawione*0.0005 - 2*btc_obstawione*0.0005; %prowizja
                ilosc_tranzakcji = ilosc_tranzakcji + 1;
            end
        end
    end
    
    kapital_history(i) = kapital;
end

subplot(2,1,1); plot(time_axis(2:length(x)), kapital_history(2:length(x)), 'b');
subplot(2,1,2);plot(time_axis(2:length(x)), z_score_history(2:length(x)), 'g');

function [beta, alpha, z_score, R_out, innovation, y_hat] = KalmanSlidingWindow123(price_eth, price_btc)
    
    persistent x P 
     
    if isempty(x)
        x = [0; 0; 0];
        P = eye(3) * 1000; 
    end
    
    %Q i R
    Q = [1425.95626582414	-16324.9322307430	0.0781794288596445;
-16324.9322307430	186909.747605727	-0.100993133807343;
0.0781794288596367	-0.100993133807140	0.0934497023763248]*1e-6; 
    A = [1 0 1; 0 1 0; 0 0 1];
    R = 0.611657306520392*1e-6;

    % predykcja
    x_pred = A*x;
    P_pred = A * P * A' + Q;
    
    H = [price_btc, 1, 0];
    y_hat = H * x_pred;
    innovation = price_eth - y_hat;
   
    % update
    S = H * P_pred * H' + R;
    K = P_pred * H' / S;
    x = x_pred + K * innovation;
    P = (eye(3) - K * H) * P_pred;
    
    % wyjścia
    beta = x(1);
    alpha = x(2);
    z_score = innovation / sqrt(S);
    R_out = R;
end

function [qty_eth, qty_btc] = CalculatePositionSize(capital_usd, price_eth, price_btc, beta)

    allocation_eth = capital_usd / 2; 
    allocation_btc = allocation_eth * beta;
    
    raw_qty_eth = allocation_eth / price_eth;
    raw_qty_btc = allocation_btc / price_btc; 
    
    % zaokrąglenie do precyzji Binance
    qty_eth = floor(raw_qty_eth * 1000) / 1000;      
    qty_btc = floor(raw_qty_btc * 100000) / 100000;  
end
