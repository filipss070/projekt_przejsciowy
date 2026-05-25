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
y = y(83976*5+4000:5:87444*5+4000); %83976:92976, 83906:87444
x = x(83976*5+4000:5:87444*5+4000);
x_log = log(x);
y_log = log(y);
time_axis = quarterly_data.Properties.RowTimes; % Oś czasu do wykresów
time_axis = time_axis(83976*5+4000:5:87444*5+4000);



stary_LL = -inf;

beta_history = zeros(1, length(x));
betasmooth_history = zeros(1, length(x));
alpha_history = zeros(1, length(x));
alphasmooth_history = zeros(1, length(x));
y_pred_history = zeros(1, length(x));
spread_history = zeros(1, length(x));
P_history = zeros(1, length(x));
Psmooth_history = zeros(1, length(x));
Pcross_history = zeros(1, length(x));
P_pred_history = zeros(1, length(x));

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
    %Q_nowe(2,2) = min(Q_nowe(1,1),1e-4);
    %Q_nowe(2,1) = 0;
    %Q_nowe(1,2) = 0;
    %Q_nowe(1,1) = min(Q_nowe(1,1),1e-6);

end

function [Q_EM, R_EM, LL_nowy1] = EM(Q_start, R_start, y, x)
    
    stary_LL = -inf;
    LL_nowy1 = 0;

    for krok = 1:100
        
        clear persistent;
    
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
Q_tymczasowy = zeros(2, 2, 100);
R_tymczasowy = zeros(1, 100);
LL_tymczasowy = zeros(1, 100);
LL_final = -inf;
%f = waitbar(0, 'losowanie:');


% A = beta*B + alfa 
aktywo_B = y_log;
aktywo_A = x_log;
%{
okno_kointegracja = 4000;

Y = [aktywo_A, aktywo_B]; 
h_eg = zeros(1,length(x)-okno_kointegracja+1);
pValue_eg = zeros(1,length(x)-okno_kointegracja+1);
for j = 1:(length(x)-okno_kointegracja+1)
    Y = [aktywo_A(j:j+okno_kointegracja-1),aktywo_B(j:j+okno_kointegracja-1)];
    [h_eg(j), pValue_eg(j)] = egcitest(Y);
    if mod(j,1000) == 0
        fprintf('\rAktualna wartość: %d', j);
    end
end

figure();
stem(h_eg);
%}

okno = 400;
innowacje_okno = zeros(1,okno);
innowacje_wariancja = zeros(1,length(x)-okno+1);
spread_wariancja = zeros(1,length(x)-okno+1);
beta_okno = zeros(1,length(x)-okno+1);
alfa_okno = zeros(1,length(x)-okno+1);
beta_alfa = zeros(1,2);

for j = 1:(length(x)-okno+1)
    beta_alfa = polyfit(aktywo_B(j:(j+okno-1)), aktywo_A(j:(j+okno-1)),1);
    beta_okno(j) = beta_alfa(1);
    alfa_okno(j) = beta_alfa(2);
    
    innowacje_okno(1:okno) = aktywo_A(j:j+okno-1) - aktywo_B(j:j+okno-1)*beta_alfa(1) - beta_alfa(2);
    innowacje_wariancja(j) = var(innowacje_okno);
end

R_start = mean(innowacje_wariancja); 
    
beta_wariancja = var(diff(beta_okno));
alfa_wariancja = var(diff(alfa_okno));


parpool();

parfor i = 1:100
    
    Q_0 = diag([beta_wariancja*(rand + 0.5), alfa_wariancja*(rand + 0.5)]);
    R_0 = R_start*(rand + 0.5);

    [Q_tymczasowy(:, :, i), R_tymczasowy(i), LL_tymczasowy(i)] = EM(Q_0,R_0,aktywo_A,aktywo_B);
    %fprintf('losowanie %d\n', i);
    %waitbar(i/100, f, sprintf('losowanie: %d/100', i));
end

delete(gcp('nocreate'));
%close(f);

for i = 1:100
        if LL_tymczasowy(i) > LL_final
            LL_final = LL_tymczasowy(i);
            Q_final = Q_tymczasowy(:, :, i);
            R_final = R_tymczasowy(i);
        end
end

figure();
stem(LL_tymczasowy);% wszystkie wartości LL, dla różnych pkt startowych

clear KalmanSlidingWindow123;

[beta_history1, alpha_history1, spread_history1, P_history1,  P_pred_history1, LL_nowy11, K_EM1] = kalman_do_przodu(aktywo_A, aktywo_B, Q_final, R_final, length(x));
[beta_history2, alpha_history2, P_pred_history2, Pcross_history2, spread_history2] = smoother(aktywo_A, aktywo_B, beta_history1, alpha_history1, P_pred_history1, P_history1, K_EM1, length(x));

XD = y_log - spread_history2';

znormalizowany_spread = zeros(1, length(spread_history1));

for i = 1:length(spread_history1)
    S = [aktywo_B(i), 1] * P_pred_history1(:,:,i) * [aktywo_B(i), 1]' + R_final;
    znormalizowany_spread(i) = spread_history1(i)/sqrt(S);
end

h = lbqtest(znormalizowany_spread);
h
[acf,lags] = autocorr(znormalizowany_spread);
figure();
stem(lags,acf);

figure();
plot(time_axis,spread_history1);

figure();
subplot(2,1,1); plot(time_axis, y_log, 'b');
subplot(2,1,2);plot(time_axis, XD, 'g');

figure();
qqplot(znormalizowany_spread);
grid on;

figure();
histogram(znormalizowany_spread(100:end));

