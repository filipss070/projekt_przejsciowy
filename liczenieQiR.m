
% Załóżmy, że pobrałeś te 3 pliki i zmieniłeś nazwy na prostsze
files_btc = {'btc_january.csv', 'btc_feb.csv', 'btc_march.csv'};
files_eth = {'eth_january.csv', 'eth_feb.csv', 'eth_march.csv'};

% --- KROK 2: Pętla wczytująca i sklejająca ---
full_btc = timetable();
full_eth = timetable();

disp('Wczytywanie i łączenie danych...');

% Opcje importu (bez nagłówków, jak wcześniej)
opts = detectImportOptions(files_btc{1}, 'NumHeaderLines', 0);
opts.VariableNamingRule = 'preserve';

for i = 1:3
    % Wczytaj pojedynczy miesiąc
    raw_b = readtable(files_btc{i}, opts);
    raw_e = readtable(files_eth{i}, opts);
    
    % Przekonwertuj na timetable (używając naszej funkcji pomocniczej)
    tt_b = prepare_binance_data(raw_b, 'BTC');
    tt_e = prepare_binance_data(raw_e, 'ETH');
    
    % DOKLEJ do głównej tabeli (Vertical Concatenation)
    % [stare_dane; nowe_dane]
    full_btc = [full_btc; tt_b];
    full_eth = [full_eth; tt_e];
end

% ZABEZPIECZENIE: Sortujemy po czasie, żeby naprawić ewentualne błędy w kolejności plików
full_btc = sortrows(full_btc);
full_eth = sortrows(full_eth);

% --- KROK 3: Synchronizacja Całości ---
disp('Synchronizacja kwartału...');
quarterly_data = synchronize(full_btc, full_eth, 'intersection');

% --- KROK 4: Obliczenie Q dla całego kwartału ---
% Teraz masz wielką tabelę 'quarterly_data' gotową do policzenia Q
% (Użyj kodu "Rolling Window" z poprzednich odpowiedzi na tej zmiennej)

disp(['Gotowe! Liczba próbek: ', num2str(height(quarterly_data))]);

% --- Funkcja pomocnicza (ta sama co wcześniej) ---
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


Q_start = [0.1 0 0; 0 0.1 0; 0 0 0.01];
R_start = 1;
stary_LL = -inf;

beta_history = zeros(1, length(x));
betasmooth_history = zeros(1, length(x));
beta1_history = zeros(1, length(x));
beta1smooth_history = zeros(1, length(x));
alpha_history = zeros(1, length(x));
alphasmooth_history = zeros(1, length(x));
y_pred_history = zeros(1, length(x));
spread_history = zeros(1, length(x));
P_history = zeros(1, length(x));
Psmooth_history = zeros(1, length(x));
Pcross_history = zeros(1, length(x));
P_pred_history = zeros(1, length(x));

function [beta, alpha, beta1, innovation, P_out, P_pred_out, LL_out, K_out] = KalmanSlidingWindow123(price_eth, price_btc, Q, R, LL_in)
    
    persistent x P 
     
    if isempty(x)
        x = [0; 0; 0];
        P = eye(3) * 1000; 
    end
    
    A = [1 0 1; 0 1 0; 0 0 1];

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
    beta1 = x(3);
    K_out = K;
    P_out = P;
    P_pred_out = P_pred;
    LL_out = LL_in - 0.5*(log(S) + (innovation^2)/S);
end

function [beta, alpha, beta1, spread, P_filtr,  P_pred_filtr, LL_nowy, K_filtr] = kalman_do_przodu(price_eth, price_btc, Q, R, length)

    beta = zeros(1, length);
    alpha = zeros(1, length);
    beta1 = zeros(1, length);
    spread = zeros(1, length);
    P_filtr = {};
    K_filtr = {};
    P_pred_filtr = {};
    LL_petla = 0;

    for i = 1:length
        [beta(i), alpha(i), beta1(i), spread(i), P_filtr{i}, P_pred_filtr{i}, nowy_LL, K_filtr{i}] = KalmanSlidingWindow123(price_eth(i), price_btc(i), Q, R, LL_petla);
        LL_petla = nowy_LL;
    end
    LL_nowy = LL_petla;
end

function [beta, alpha, beta1, P, P_cross, spread] = smoother(price_eth, price_btc, beta_in, alpha_in, beta1_in, P_pred_in, P_in, K_in, length) 

    beta = zeros(1, length);
    alpha = zeros(1, length);
    beta1 = zeros(1, length);
    spread = zeros(1, length);
    A = [1 0 1; 0 1 0; 0 0 1];
    P = {};
    P_cross = {};
    
    beta(length) = beta_in(length);
    alpha(length) = alpha_in(length);
    beta1(length) = beta1_in(length);
    P{length} = P_in{length};
    P_cross{length} = (eye(3)- K_in{length} * [price_btc(length), 1, 0]) * A * P_in{length}; 

    for i = length:-1:2
        C = P_in{i-1} * A' / P_pred_in{i};
        x = [beta_in(i-1); alpha_in(i-1); beta1_in(i-1)] + C * ([beta(i); alpha(i); beta1(i)] - A * [beta_in(i-1); alpha_in(i-1); beta1_in(i-1)]);
        P{i-1} = P_in{i-1} + C * (P{i} - P_pred_in{i}) * C';
        H = [price_btc(i), 1, 0];
        spread(i) = price_eth(i) - H * x;
        beta(i-1) = x(1);
        alpha(i-1) = x(2);
        beta1(i-1) = x(3);
    end

    for j = length:-1:3
        C = P_in{j-1} * A' / P_pred_in{j};
        C1 = P_in{j-2} * A' / P_pred_in{j-1};
        P_cross{j-1} = P_in{j-1}*C1' + C * (P_cross{j} - A*P_pred_in{j-1}) * C1'; 
    end

end

function [Q_nowe, R_nowe] = wyliczanie_QR(price_btc, beta, alpha, beta1, P, P_cross, spread, length)
    
    R = 0;
    A = [1 0 1; 0 1 0; 0 0 1];
    A1 = zeros(3, 3);
    B1 = zeros(3, 3);
    C1 = zeros(3, 3);

    for i = 3:length
        H = [price_btc(i), 1, 0];
        x = [beta(i); alpha(i); beta1(i)];
        x1 = [beta(i-1); alpha(i-1); beta1(i-1)];
        A1 = A1 + P{i-1} + x1*x1';
        B1 = B1 + P_cross{i} + x*x1';
        C1 = C1 + P{i} + x*x';
        R = R + (spread(i)^2 + H * P{i} * H')/(length-2);   
    end

    Q_nowe = (C1-(B1/A1)*B1' + (B1/A1 - A)*A1*(B1/A1 - A)')/(length-2);
    R_nowe = R;

end

for krok = 1:100
    
    clear KalmanSlidingWindow123;

    [beta_history, alpha_history, beta1_history, spread_history, P_history,  P_pred_history, LL_nowy1, K_EM] = kalman_do_przodu(y_log, x_log, Q_start, R_start, length(x));

    roznica = LL_nowy1 - stary_LL;
    if roznica < 0.0001
        disp('koniec')
        break;
    end
    
    stary_LL = LL_nowy1;

    [betasmooth_history, alphasmooth_history, beta1smooth_history, Psmooth_history, Pcross_history, spread_history] = smoother(y_log, x_log, beta_history, alpha_history, beta1_history, P_pred_history, P_history, K_EM, length(x));

    [Q_start, R_start] = wyliczanie_QR(x_log, betasmooth_history, alphasmooth_history, beta1smooth_history, Psmooth_history, Pcross_history, spread_history, length(x));

end

[beta_history1, alpha_history1, beta1_history1, spread_history1, P_history1,  P_pred_history1, LL_nowy11] = kalman_do_przodu(y_log, x_log, Q_start, R_start, length(x));
[beta_history2, alpha_history2, beta1_history2, P_pred_history2, Pcross_history2, spread_history2] = smoother(y_log, x_log, beta_history1, alpha_history1, beta1_history1, P_pred_history1, P_history1, K_EM, length(x));

XD = y_log - spread_history2';
subplot(2,1,1); plot(time_axis, y_log, 'b');
subplot(2,1,2);plot(time_axis, XD, 'g');
