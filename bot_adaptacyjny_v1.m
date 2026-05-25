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

function [beta, alpha, innovation, P_out, P_pred_out, LL_out, K_out] = KalmanSlidingWindow123(price_eth, price_btc, Q, R, LL_in, x_in, P_in)
    
    A = [1 0 ; 0 1];

    % predykcja
    x_pred = A*x_in;
    P_pred = A * P_in * A' + Q;
    
    H = [price_btc, 1];
    y_hat = H * x_pred;
    innovation = price_eth - y_hat; 
   
    % update
    S = H * P_pred * H' + R;
    if S <= 0
        beta = 0; alpha = 0; innovation = 0;
        P_out = P_in; K_out = [0;0]; P_pred_out = P_pred;
        LL_out = -inf;
        return;
    end
    K = P_pred * H' / S;
    x = x_pred + K * innovation;
    P = (eye(2) - K * H) * P_pred;
    
    % wyjścia
    beta = x(1);
    alpha = x(2);
    K_out = K;
    P_out = P;
    P_pred_out = P_pred;
    LL_out = LL_in - 0.5*(log(S) + (innovation^2)/S);
end

function [beta, alpha, spread, P_filtr,  P_pred_filtr, LL_nowy, K_filtr] = kalman_do_przodu(price_eth, price_btc, Q, R, length)

    beta = zeros(1, length);
    alpha = zeros(1, length);
    spread = zeros(1, length);
    P_filtr = zeros(2, 2, length);
    K_filtr = zeros(2, 1, length);
    P_pred_filtr = zeros(2, 2, length);
    LL_petla = 0;

    x_petla = [0; 0];
    P_petla = eye(2)*1;

    for i = 1:length
        [beta(i), alpha(i), spread(i), P_filtr(:, :, i), P_pred_filtr(:, :, i), nowy_LL, K_filtr(:, :, i)] = KalmanSlidingWindow123(price_eth(i), price_btc(i), Q, R, LL_petla, x_petla, P_petla);
        LL_petla = nowy_LL;
        x_petla = [beta(i); alpha(i)];
        P_petla = P_filtr(:,:,i);
        if LL_petla == -inf
            LL_nowy = -inf;
            return;
        end
    end
    LL_nowy = LL_petla;
end

function [beta, alpha, P, P_cross, spread] = smoother(price_eth, price_btc, beta_in, alpha_in, P_pred_in, P_in, K_in, length) 

    beta = zeros(1, length);
    alpha = zeros(1, length);
    spread = zeros(1, length);
    A = [1 0 ; 0 1];
    P = zeros(2, 2, length);
    P_cross = zeros(2, 2, length);
    
    beta(length) = beta_in(length);
    alpha(length) = alpha_in(length);
    P(:, :, length) = P_in(:, :, length);
    P_cross(:, :, length) = (eye(2)- K_in(:, :, length) * [price_btc(length), 1]) * A * P_in(:, :, length-1); 

    for i = length:-1:2
        C = P_in(:, :, i-1) * A' / P_pred_in(:, :, i);
        x = [beta_in(i-1); alpha_in(i-1)] + C * ([beta(i); alpha(i)] - A * [beta_in(i-1); alpha_in(i-1)]);
        P(:, :, i-1) = P_in(:, :, i-1) + C * (P(:, :, i) - P_pred_in(:, :, i)) * C';
        H = [price_btc(i), 1];
        spread(i) = price_eth(i) - H * x;
        beta(i-1) = x(1);
        alpha(i-1) = x(2);
    end

    for j = length:-1:3
        C = P_in(:, :, j-1) * A' / P_pred_in(:, :, j);
        C1 = P_in(:, :, j-2) * A' / P_pred_in(:, :, j-1);
        P_cross(:, :, j-1) = P_in(:, :, j-1)*C1' + C * (P_cross(:, :, j) - A*P_pred_in(:, :, j-1)) * C1'; 
    end

end

function [Q_nowe, R_nowe] = wyliczanie_QR(price_btc, beta, alpha, P, P_cross, spread, length)
    
    R = 0;
    A = [1 0 ; 0 1];
    A1 = zeros(2, 2);
    B1 = zeros(2, 2);
    C1 = zeros(2, 2);

    for i = 3:length
        H = [price_btc(i), 1];
        x = [beta(i); alpha(i)];
        x1 = [beta(i-1); alpha(i-1)];
        A1 = A1 + P(:, :, i-1) + x1*x1';
        B1 = B1 + P_cross(:, :, i) + x*x1';
        C1 = C1 + P(:, :, i) + x*x';
        R = R + (spread(i)^2 + H * P(:, :, i) * H')/(length-2);   
    end

    Q_nowe = (C1-(B1/A1)*B1' + (B1/A1 - A)*A1*(B1/A1 - A)')/(length-2);
    R_nowe = R;
    %ograniczenia
    %Q_nowe(2,2) = min(Q_nowe(1,1),1e-6);
    %Q_nowe(2,1) = 0;
    %Q_nowe(1,2) = 0;
    %Q_nowe(1,1) = min(Q_nowe(1,1),1e-4);

end

function [Q_EM, R_EM, LL_nowy1] = EM(Q_start, R_start, y, x)
    
    stary_LL = -inf;
    LL_nowy1 = 0;

    for krok = 1:100
            
        [beta_history, alpha_history, spread_history, P_history,  P_pred_history, LL_nowy1, K_EM] = kalman_do_przodu(y, x, Q_start, R_start, length(x));
    
        roznica = LL_nowy1 - stary_LL;
        if roznica < 0.0001 || LL_nowy1 == -inf
            %disp('koniec')
            break;
        end
        
        stary_LL = LL_nowy1;
    
        [betasmooth_history, alphasmooth_history, Psmooth_history, Pcross_history, spread_history] = smoother(y, x, beta_history, alpha_history, P_pred_history, P_history, K_EM, length(x));
    
        [Q_start, R_start] = wyliczanie_QR(x, betasmooth_history, alphasmooth_history, Psmooth_history, Pcross_history, spread_history, length(x));
    
    end
    
    Q_EM = Q_start;
    R_EM = R_start;
end

Q_final = [];
R_final = 0;
Q_tymczasowy = zeros(2, 2, 20);
R_tymczasowy = zeros(1, 20);
LL_tymczasowy = zeros(1, 20);
LL_final = -inf;

Q_final1 = [];
R_final1 = 0;
Q_tymczasowy1 = zeros(2, 2, 20);
R_tymczasowy1 = zeros(1, 20);
LL_tymczasowy1 = zeros(1, 20);
LL_final1 = -inf;
%f = waitbar(0, 'losowanie:');

% A = beta*B + alfa 
aktywo_B = y_log;
aktywo_A = x_log;
aktywo_B1 = y;
aktywo_A1 = x;

okno_kointegracja = 288*7;

Y = [aktywo_A, aktywo_B]; 
h_eg = zeros(1,length(x));
pValue_eg = zeros(1,length(x));
for j = 1:(length(x)-okno_kointegracja) % w sumie okno to tydzien + 1
    Y = [aktywo_A(j:j+okno_kointegracja),aktywo_B(j:j+okno_kointegracja)];
    [h_eg(j+okno_kointegracja), pValue_eg(j+okno_kointegracja)] = egcitest(Y);
    if mod(j,1000) == 0
        fprintf('\rAktualna wartość: %d', j);
    end
end

figure();
stem(h_eg);

okno = 400;
%okno = 100;
innowacje_okno = zeros(1,okno);
innowacje_wariancja = zeros(1,288*7-okno);
beta_okno = zeros(1,288*7-okno);
alfa_okno = zeros(1,288*7-okno);
beta_alfa = zeros(1,2);

innowacje_okno1 = zeros(1,okno);
innowacje_wariancja1 = zeros(1,288*7-okno);
beta_okno1 = zeros(1,288*7-okno);
alfa_okno1 = zeros(1,288*7-okno);
beta_alfa1 = zeros(1,2);

for j = 1:(288*7)
    beta_alfa = polyfit(aktywo_B(j:(j+okno-1)), aktywo_A(j:(j+okno-1)),1);
    beta_okno(j) = beta_alfa(1);
    alfa_okno(j) = beta_alfa(2);
    
    innowacje_okno(1:okno) = aktywo_A(j:j+okno-1) - aktywo_B(j:j+okno-1)*beta_alfa(1) - beta_alfa(2);
    innowacje_wariancja(j) = var(innowacje_okno);

    beta_alfa1 = polyfit(aktywo_A(j:(j+okno-1)), aktywo_B(j:(j+okno-1)),1);
    beta_okno1(j) = beta_alfa1(1);
    alfa_okno1(j) = beta_alfa1(2);
    
    innowacje_okno1(1:okno) = aktywo_B(j:j+okno-1) - aktywo_A(j:j+okno-1)*beta_alfa1(1) - beta_alfa1(2);
    innowacje_wariancja1(j) = var(innowacje_okno1);
end

R_start = mean(innowacje_wariancja); 
    
beta_wariancja = var(diff(beta_okno));
alfa_wariancja = var(diff(alfa_okno));

R_start1 = mean(innowacje_wariancja); 
    
beta_wariancja1 = var(diff(beta_okno));
alfa_wariancja1 = var(diff(alfa_okno));

beta_history = zeros(1, length(x));
alpha_history = zeros(1, length(x));
y_pred_history = zeros(1, length(x));
spread_history = zeros(1, length(x));
z_score_history = zeros(1, length(x));
R_history = zeros(1, length(x));

beta_history1 = zeros(1, length(x));
alpha_history1 = zeros(1, length(x));
y_pred_history1 = zeros(1, length(x));
spread_history1 = zeros(1, length(x));
z_score_history1 = zeros(1, length(x));
R_history1 = zeros(1, length(x));


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
h_adf = 0;
h_adf_history = zeros(1,length(x));

R1 = R_start;
Q1 = diag([beta_wariancja, alfa_wariancja]);

R2 = R_start1;
Q2 = diag([beta_wariancja1, alfa_wariancja1]);

x_loop = [];
P_loop = [];

x_loop1 = [];
P_loop1 = [];

clear KalmanSlidingWindow1234;

for i = 288*7:length(x)

    if not(mod(i,288*2))
        poolobj = gcp('nocreate');
        if isempty(poolobj)
            disp('Uruchamianie puli równoległej po raz pierwszy...');
            parpool('local', 'IdleTimeout', Inf);
        end
        
        for j = 1:288*7-okno
            beta_alfa = polyfit(aktywo_B(i-288*7+j:i-288*7+j+okno-1), aktywo_A(i-288*7+j:i-288*7+j+okno-1),1);
            beta_okno(j) = beta_alfa(1);
            alfa_okno(j) = beta_alfa(2);
            
            innowacje_okno(1:okno) = aktywo_A(i-288*7+j:i-288*7+j+okno-1) - aktywo_B(i-288*7+j:i-288*7+j+okno-1)*beta_alfa(1) - beta_alfa(2);
            innowacje_wariancja(j) = var(innowacje_okno);

            beta_alfa1 = polyfit(aktywo_A(i-288*7+j:i-288*7+j+okno-1), aktywo_B(i-288*7+j:i-288*7+j+okno-1),1);
            beta_okno1(j) = beta_alfa1(1);
            alfa_okno1(j) = beta_alfa1(2);
            
            innowacje_okno1(1:okno) = aktywo_B(i-288*7+j:i-288*7+j+okno-1) - aktywo_A(i-288*7+j:i-288*7+j+okno-1)*beta_alfa1(1) - beta_alfa1(2);
            innowacje_wariancja1(j) = var(innowacje_okno1);
        end

        R_start = mean(innowacje_wariancja); 
            
        beta_wariancja = var(diff(beta_okno));
        alfa_wariancja = var(diff(alfa_okno));

        R_start1 = mean(innowacje_wariancja); 
            
        beta_wariancja1 = var(diff(beta_okno));
        alfa_wariancja1 = var(diff(alfa_okno));

        x_startowe = [beta_alfa(1); beta_alfa(2)];
        P_startowe = diag([beta_wariancja, alfa_wariancja]); %w teorii to jest Q, ale to pewnie też jest ok punktem startowym
        okno_A = aktywo_A((i-288*7+1:i));
        okno_B = aktywo_B((i-288*7+1:i));


        parfor k = 1:20
            
            Q_0 = diag([beta_wariancja*(rand + 0.5), alfa_wariancja*(rand + 0.5)]);
            R_0 = R_start*(rand + 0.5);

            Q_01 = diag([beta_wariancja1*(rand + 0.5), alfa_wariancja1*(rand + 0.5)]);
            R_01 = R_start1*(rand + 0.5);
            
            [Q_tymczasowy(:, :, k), R_tymczasowy(k), LL_tymczasowy(k)] = EM(Q_0,R_0,okno_A,okno_B);
            [Q_tymczasowy1(:, :, k), R_tymczasowy1(k), LL_tymczasowy1(k)] = EM(Q_0,R_0,okno_B,okno_A);
            %fprintf('losowanie %d\n', i);
            %waitbar(i/100, f, sprintf('losowanie: %d/100', i));
        end
       
        %close(f);
        LL_final=-inf;
        LL_final1=-inf;
        
        for j = 1:20
                if LL_tymczasowy(j) > LL_final
                    LL_final = LL_tymczasowy(j);
                    Q_final = Q_tymczasowy(:, :, j);
                    R_final = R_tymczasowy(j);
                end
        end

        for j = 1:20
                if LL_tymczasowy1(j) > LL_final1
                    LL_final1 = LL_tymczasowy1(j);
                    Q_final1 = Q_tymczasowy1(:, :, j);
                    R_final1 = R_tymczasowy1(j);
                end
        end
        
        Q1 = Q_final;
        R1 = R_final;

        Q2 = Q_final1;
        R2 = R_final1;
    end

    [beta_history(i), alpha_history(i), z_score_history(i), R_history(i), spread_history(i), y_pred_history(i), x_loop, P_loop] = KalmanSlidingWindow1234(aktywo_A(i),aktywo_B(i), Q1, R1, x_loop, P_loop);
    [beta_history1(i), alpha_history1(i), z_score_history1(i), R_history1(i), spread_history1(i), y_pred_history1(i), x_loop1, P_loop1] = KalmanSlidingWindow1234(aktywo_B(i),aktywo_A(i), Q2, R2, x_loop1, P_loop1);
    
    %if i > 288*7 && not(mod(i,5))%ADF check
    %    h_adf = egcitest([aktywo_A(i-499:i), aktywo_B(i-499:i)]);
    %end

    %h_adf_history(i) = h_adf;
    %{
    if tranzakcja == false && h_adf 
        
        if z_score_history(i) > 0.05% && z_score_history1(i) < -0.05  % sprawdzenie czy wyniki kalmanów są mniej więcej takie same % && abs(spread_history(i))/y(i) > min_profit
            [ilosc_eth, ilosc_btc] = CalculatePositionSize(kapital, aktywo_A1(i), aktywo_B1(i), beta_history(i));
            tranzakcja = true;
            eth_obstawione = aktywo_A1(i)*ilosc_eth;
            btc_obstawione = aktywo_B1(i)*ilosc_btc;
            cena_eth_w_momencie_obstawiania = aktywo_A1(i);
            cena_btc_w_momencie_obstawiania = aktywo_B1(i);
            zscore2 = true;
        elseif z_score_history(i) < -0.05% && z_score_history1(i) > 0.05 %&& abs(spread_history(i))/y(i) > min_profit
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
            if z_score_history(i) < 0 %&& (cena_eth_w_momencie_obstawiania-y(i))*eth_obstawione/cena_eth_w_momencie_obstawiania - (cena_btc_w_momencie_obstawiania-x(i))*btc_obstawione/cena_btc_w_momencie_obstawiania - 2*eth_obstawione*0.0005 - 2*btc_obstawione*0.0005 > 0
                zscore2 = false;
                tranzakcja = false;
                kapital = kapital + (cena_eth_w_momencie_obstawiania-aktywo_A1(i))*eth_obstawione/cena_eth_w_momencie_obstawiania - (cena_btc_w_momencie_obstawiania-aktywo_B1(i))*btc_obstawione/cena_btc_w_momencie_obstawiania;% - 2*eth_obstawione*0.0005 - 2*btc_obstawione*0.0005; %prowizja
                ilosc_tranzakcji = ilosc_tranzakcji + 1;
            end
        elseif zscoreneg2 == true
            if z_score_history(i) > 0 %&& (y(i)-cena_eth_w_momencie_obstawiania)*eth_obstawione/cena_eth_w_momencie_obstawiania - (x(i)-cena_btc_w_momencie_obstawiania)*btc_obstawione/cena_btc_w_momencie_obstawiania - 2*eth_obstawione*0.0005 - 2*btc_obstawione*0.0005 > 0
                zscoreneg2 = false;
                tranzakcja = false;
                kapital = kapital + (aktywo_A1(i)-cena_eth_w_momencie_obstawiania)*eth_obstawione/cena_eth_w_momencie_obstawiania - (aktywo_B1(i)-cena_btc_w_momencie_obstawiania)*btc_obstawione/cena_btc_w_momencie_obstawiania;% - 2*eth_obstawione*0.0005 - 2*btc_obstawione*0.0005; %prowizja
                ilosc_tranzakcji = ilosc_tranzakcji + 1;
            end
        end
    end
    
    kapital_history(i) = kapital;
    %}
    if mod(i,100) == 0
        fprintf('\rAktualna wartość: %d', i);
    end
end

delete(gcp('nocreate'));

function [beta, alpha, z_score, R_out, innovation, y_hat, x_out, P_out] = KalmanSlidingWindow1234(price_eth, price_btc, Q, R, x_in, P_in)
    
   
    if isempty(x_in)
        x_in = [0; 0];
        P_in = eye(2) * 1; 
    end
    
    %Q i R 
    A = [1 0; 0 1];
    

    % predykcja
    x_pred = A*x_in;
    P_pred = A * P_in * A' + Q;
    
    H = [price_btc, 1];
    y_hat = H * x_pred;
    innovation = price_eth - y_hat;
   
    % update
    S = H * P_pred * H' + R;
    K = P_pred * H' / S;
    x_out = x_pred + K * innovation;
    P_out = (eye(2) - K * H) * P_pred;

    
    % wyjścia
    beta = x_out(1);
    alpha = x_out(2);
    z_score = innovation / sqrt(S);
    R_out = R;
end

function [qty_eth, qty_btc] = CalculatePositionSize(capital_usd, price_eth, price_btc, beta)

    allocation_eth = capital_usd / (1 + beta); 
    allocation_btc = capital_usd - allocation_eth;
    
    qty_eth = allocation_eth / price_eth;
    qty_btc = allocation_btc / price_btc; 
    
end