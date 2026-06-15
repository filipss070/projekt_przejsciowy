
disp('Skanowanie folderu w poszukiwaniu plików CSV...');
folder_dane = 'C:\Users\filip\Documents\PCA\dane_do_PCA';

% 1. Odczyt wszystkich plików i wyciągnięcie unikalnych tickerów
wszystkie_pliki = dir(fullfile(folder_dane, '*.csv'));
if isempty(wszystkie_pliki)
    error('Nie znaleziono żadnych plików .csv!');
end

% Wyciągamy nazwy walut z plików (np. "BTCUSDT" z "BTCUSDT-1m-2023-01.csv")
nazwy_plikow = {wszystkie_pliki.name};
waluty = cell(1, length(nazwy_plikow));
for i = 1:length(nazwy_plikow)
    czesci = split(nazwy_plikow{i}, '-');
    waluty{i} = czesci{1};
end

unikalne_waluty = unique(waluty);
liczba_walut = length(unikalne_waluty);
disp(['Znaleziono unikalnych kryptowalut: ', num2str(liczba_walut)]);

% Opcje importu zdefiniowane raz
opts = detectImportOptions(fullfile(wszystkie_pliki(1).folder, wszystkie_pliki(1).name), 'NumHeaderLines', 0);
opts.VariableNamingRule = 'preserve';

% 2. Prealokacja głównej komórki na gotowe osie czasu wszystkich walut
master_tt = cell(liczba_walut, 1);

disp('Wczytywanie i układanie danych dla każdej waluty (to może potrwać)...');

% 3. Główna pętla ładująca (Automatyzacja)
for w = 1:liczba_walut
    obecna_waluta = unikalne_waluty{w};
   
    % Szukamy plików tylko dla tej konkretnej waluty
    pliki_waluty = dir(fullfile(folder_dane, [obecna_waluta, '-*.csv']));
    dane_tymczasowe = cell(length(pliki_waluty), 1);
   
    for p = 1:length(pliki_waluty)
        sciezka = fullfile(pliki_waluty(p).folder, pliki_waluty(p).name);
        raw_data = readtable(sciezka, opts);
        dane_tymczasowe{p} = prepare_binance_data(raw_data, obecna_waluta);
    end
   
    % Sklejamy wszystkie miesiące dla tej jednej waluty i sortujemy chronologicznie
    pelna_historia = vertcat(dane_tymczasowe{:});
    master_tt{w} = sortrows(pelna_historia);
   
    disp([' -> Wczytano ', obecna_waluta, ' (', num2str(w), '/', num2str(liczba_walut), ')']);
end

% 4. Synchronizacja wszystkiego do jednej, potężnej macierzy
disp('Synchronizacja osi czasu dla wszystkich 50 walut naraz...');
% UWAGA: Używamy 'union', aby nie stracić danych, jeśli jakiejś waluty brakowało
dane_zsynch = synchronize(master_tt{:}, 'union');

clear master_tt;

disp('Łatanie ewentualnych dziur w notowaniach na giełdzie...');
% Zastępujemy braki ($NaN$) metodą 'previous' (czyli utrzymujemy cenę z poprzedniej minuty)
dane_zsynch = fillmissing(dane_zsynch, 'previous');
% Na koniec wyrzucamy wiersze, gdzie nadal są luki (np. przed powstaniem danej waluty)
dane_zsynch = rmmissing(dane_zsynch);

disp(['Gotowe! Ostateczny rozmiar tabeli: ', num2str(height(dane_zsynch)), ' minut.']);

% W tym momencie 'dane_zsynch' to gotowa tabela ze wszystkimi walutami jako kolumnami.
% Aby wyciągnąć czystą macierz numeryczną dla algorytmu PCA (bez dat):


function tt_out = prepare_binance_data(raw_table, label)
    timestamps = raw_table.(1); 
    close_prices = raw_table.(5);
    
    % Sprawdzenie rzędu wielkości, aby dynamicznie dobrać dzielnik
    mediana_czasu = median(timestamps, 'omitnan');
    
    if mediana_czasu > 1e15
        % Wartość powyżej 1 biliona -> to są mikrosekundy
        dzielnik = 1000000;
    elseif mediana_czasu > 1e11
        % Wartość w okolicach biliona (13 cyfr) -> to są milisekundy (standard Binance)
        dzielnik = 1000;
    else
        % Wartość 10-cyfrowa -> to są zwykłe sekundy
        dzielnik = 1;
    end
    
    % Konwersja z odpowiednim dzielnikiem
    dates = datetime(timestamps/dzielnik, 'ConvertFrom', 'posixtime');
    
    col_name = strcat('Close_', label);
    tt_out = timetable(dates, close_prices, 'VariableNames', {col_name});
end

% KROK A: Wypełnianie NaN ostatnią znaną próbką
disp('Łatanie luk (NaN) na podstawie poprzednich znanych cen...');
dane_zsynch = fillmissing(dane_zsynch, 'previous');

% Usuwamy wiersze na samym początku historii, gdzie waluta jeszcze nie istniała
% (wtedy nie ma "poprzedniej" wartości, więc NaN zostaje na górze tabeli)
dane_zsynch = rmmissing(dane_zsynch);

% KROK B: Konwersja na interwał 5-minutowy
disp('Resampling danych do interwału 5-minutowego...');
% Funkcja retime próbkuj co 5 minut i dla pewności bierze ostatnią znaną wartość
dane_60m = retime(dane_zsynch, 'regular', 'previous', 'TimeStep', minutes(60));

disp(['Gotowe! Ostateczny rozmiar tabeli 5m: ', num2str(height(dane_60m)), ' próbek.']);
clear dane_zsynch;

time_axis = dane_60m.Properties.RowTimes;

macierz_cen = dane_60m.Variables;

function [x, innovation, P, P_pred, LL_out, K] = KalmanSlidingWindow123(A, H, Q, R, LL_in, x_in, P_in, zmienna_mierzona)
    
    % predykcja
    x_pred = A*x_in;
    P_pred = A * P_in * A' + Q;
    
    y_hat = H * x_pred;
    innovation = zmienna_mierzona - y_hat; 
   
    % update
    S = H * P_pred * H' + R;
    if S <= 0
        innovation = 0;
        P = P_in; K = [0;0];
        LL_out = -inf;
        return;
    end
    K = P_pred * H' / S;
    x = x_pred + K * innovation;
    P = (eye(size(A, 1)) - K * H) * P_pred;
    
    % wyjścia
    LL_out = LL_in - 0.5*(log(S) + (innovation^2)/S);
end

function [z_score, innovation, y_hat, x, P] = KalmanSlidingWindow1234(A, H, Q, R, x_in, P_in, zmienna_mierzona)
    
    % predykcja
    x_pred = A*x_in;
    P_pred = A * P_in * A' + Q;
    
    y_hat = H * x_pred;
    innovation = zmienna_mierzona - y_hat; 
   
    % update
    S = H * P_pred * H' + R;
    if S <= 0
        innovation = 0;
        P = P_in; K = [0;0];
        LL_out = -inf;
        return;
    end
    K = P_pred * H' / S;
    x = x_pred + K * innovation;
    P = (eye(size(A, 1)) - K * H) * P_pred;
    z_score = innovation/sqrt(S);
end

function [x, spread, P_filtr,  P_pred_filtr, LL_nowy, K_filtr, H] = kalman_do_przodu(A, wektory_cen, Q, R, pomiar, length)
    
    x = zeros(size(A,1), length);
    spread = zeros(1, length);
    P_filtr = zeros(size(A,1), size(A,1), length);
    K_filtr = zeros(size(A,1), 1, length);
    P_pred_filtr = zeros(size(A,1), size(A,1), length);
    LL_petla = 0;
    
    H = [ones(size(wektory_cen,1),1) wektory_cen];
        
    x_petla = zeros(size(A,1),1);
    P_petla = eye(size(A,1));

    for i = 1:length
        [x(:,i), spread(i), P_filtr(:, :, i), P_pred_filtr(:, :, i), nowy_LL, K_filtr(:, :, i)] = KalmanSlidingWindow123(A, H(i,:), Q, R, LL_petla, x_petla, P_petla, pomiar(i));
        LL_petla = nowy_LL;
        x_petla = x(:,i);
        P_petla = P_filtr(:,:,i);
        if LL_petla == -inf
            LL_nowy = -inf;
            return;
        end
    end
    LL_nowy = LL_petla;
end

function [x_out, P, P_cross, spread] = smoother(A, H, x_in, P_pred_in, P_in, K_in, zmienna_mierzona, length) 

    x_out = zeros(size(A,1), length);
    x_out(:,length) = x_in(:,length);
    spread = zeros(1, length);
    P = zeros(size(A,1), size(A,1), length);
    P_cross = zeros(size(A,1), size(A,1), length);
    
    P(:, :, length) = P_in(:, :, length);
    P_cross(:, :, length) = (eye(size(A, 1))- K_in(:, :, length) * H(length,:)) * A * P_in(:, :, length-1); 

    for i = length:-1:2
        C = P_in(:, :, i-1) * A' / P_pred_in(:, :, i);
        x_out(:,i-1) = x_in(:,i-1) + C * (x_out(:,i) - A * x_in(:,i-1));
        P(:, :, i-1) = P_in(:, :, i-1) + C * (P(:, :, i) - P_pred_in(:, :, i)) * C';
        spread(i) = zmienna_mierzona(i) - H(i,:) * x_out(:,i);
    end

    for j = length:-1:3
        C = P_in(:, :, j-1) * A' / P_pred_in(:, :, j);
        C1 = P_in(:, :, j-2) * A' / P_pred_in(:, :, j-1);
        P_cross(:, :, j-1) = P_in(:, :, j-1)*C1' + C * (P_cross(:, :, j) - A*P_pred_in(:, :, j-1)) * C1'; 
    end

end

function [Q_nowe, R_nowe] = wyliczanie_QR(A, H, x, P, P_cross, spread, length)
    
    R = 0;
    A1 = zeros(size(A,1), size(A,1));
    B1 = zeros(size(A,1), size(A,1));
    C1 = zeros(size(A,1), size(A,1));

    for i = 3:length
        x1 = x(:,i-1);
        A1 = A1 + P(:, :, i-1) + x1*x1';
        B1 = B1 + P_cross(:, :, i) + x(:,i)*x1';
        C1 = C1 + P(:, :, i) + x(:,i)*x(:,i)';
        R = R + (spread(i)^2 + H(i,:) * P(:, :, i) * H(i,:)')/(length-2);   
    end

    Q_nowe = (C1-(B1/A1)*B1' + (B1/A1 - A)*A1*(B1/A1 - A)')/(length-2);
    R_nowe = R;
    %ograniczenia
    %Q_nowe(2,2) = min(Q_nowe(1,1),1e-6);
    %Q_nowe(2,1) = 0;
    %Q_nowe(1,2) = 0;
    %Q_nowe(1,1) = min(Q_nowe(1,1),1e-4);
end


function [Q_EM, R_EM, LL_nowy1] = EM(A_in, Q_start, R_start, ceny_PCA, estymowana_waluta)
    
    stary_LL = -inf;
    LL_nowy1 = 0;

    for krok = 1:100
            
        [x_history, spread_history, P_history,  P_pred_history, LL_nowy1, K_EM, H_history] = kalman_do_przodu(A_in, ceny_PCA, Q_start, R_start, estymowana_waluta, size(ceny_PCA,1));
    
        roznica = LL_nowy1 - stary_LL;
        if roznica < 0.0001 || LL_nowy1 == -inf
            %disp('koniec')
            break;
        end
        
        stary_LL = LL_nowy1;
    
        [x_smooth_history, Psmooth_history, Pcross_history, spread_history] = smoother(A_in, H_history, x_history, P_pred_history, P_history, K_EM, estymowana_waluta, size(ceny_PCA,1));
    
        [Q_start, R_start] = wyliczanie_QR(A_in, H_history, x_smooth_history, Psmooth_history, Pcross_history, spread_history, size(ceny_PCA,1));
    
    end
    
    Q_EM = Q_start;
    R_EM = R_start;
end

function [wektory_wlasne_k, wektory_wlasne_do_cen] = PCA(macierz_cen, k, poprzednie_wektory)
    
    macierz_zwrotow = zeros(size(macierz_cen, 1)-1, size(macierz_cen, 2));
    wektor_odwrotnych_odchylen = zeros(size(macierz_cen,2), 1);

    for j = 1:size(macierz_cen, 2)
        macierz_zwrotow(:, j) = (diff(log(macierz_cen(:, j))) - mean(diff(log(macierz_cen(:, j)))))/std(diff(log(macierz_cen(:, j)))); 
        wektor_odwrotnych_odchylen(j) = 1/std(diff(log(macierz_cen(:, j))));
    end
    
    R = macierz_zwrotow'*macierz_zwrotow/(size(macierz_zwrotow, 1)-1);
    [wektory_wlasne, lambda] = eig(R);

    wektory_wlasne_k = zeros(size(R,1), k);
    wektory_wlasne_do_cen = zeros(size(R,1), k);
    
    [~,wartosci_wlasne_indeksy] = maxk(abs(diag(lambda)), k);
    
    for i = 1:k
        wektory_wlasne_k(:,i) = wektory_wlasne(:,wartosci_wlasne_indeksy(i));
        wektory_wlasne_do_cen(:,i) = wektory_wlasne(:,wartosci_wlasne_indeksy(i))./wektor_odwrotnych_odchylen;
    end
    
    if ~isempty(poprzednie_wektory)
        for i = 1:k
            if dot(wektory_wlasne_k(:, i), poprzednie_wektory(:, i)) < -0.5
                wektory_wlasne_k(:, i) = -wektory_wlasne_k(:, i);
                wektory_wlasne_do_cen(:, i) = -wektory_wlasne_do_cen(:, i);
            end
        end
    end

    
end

log_ceny = log(macierz_cen);
log_waluta_estymowana = log(macierz_cen(:,6));
liczba_komponentow = 4;
A_wej = eye(liczba_komponentow+1);
syntetyczne_ceny = zeros(liczba_komponentow, size(macierz_cen, 1));

okno_MLR = 50;
okno_EM_PCA = 24*14;
czestotliwosc_PCA_EM = 12;
offset  = 24*14;
innowacje_okno = zeros(okno_MLR,1);
innowacje_wariancja = zeros(1,okno_EM_PCA-okno_MLR);
beta_okno = zeros(liczba_komponentow+1,okno_EM_PCA-okno_MLR);

[~,wektory_wlasne] = PCA(macierz_cen(1:okno_EM_PCA,:), liczba_komponentow, []);

for k = okno_EM_PCA+1:(okno_EM_PCA*2)
    if not(mod(k,czestotliwosc_PCA_EM))
        [~,wektory_wlasne] = PCA(macierz_cen(k-okno_EM_PCA+1:k,:), liczba_komponentow, wektory_wlasne);
    end
    syntetyczne_ceny(:,k) = syntetyczne_ceny(:,k-1) + wektory_wlasne' * (log(macierz_cen(k,:)) - log(macierz_cen(k-1,:)))';
end


for j = 1:(okno_EM_PCA-okno_MLR)

    X_OLS = [ones(okno_MLR, 1) syntetyczne_ceny(:,offset+j:offset+j+okno_MLR-1)'];
    beta_okno(:,j) = (X_OLS'*X_OLS)\X_OLS'*log_waluta_estymowana(offset+j:offset+j+okno_MLR-1);
    
    innowacje_okno = log_waluta_estymowana(offset+j:offset+j+okno_MLR-1) - X_OLS*beta_okno(:,j);
    innowacje_wariancja(j) = var(innowacje_okno);
end

R_start = mean(innowacje_wariancja); 
    
beta_wariancja = var(diff(beta_okno'),0,1);
Q_start = diag(beta_wariancja);

x_history = zeros(liczba_komponentow+1,size(macierz_cen, 1));
z_score_history = zeros(1,size(macierz_cen, 1));
spread_history = zeros(1,size(macierz_cen, 1));
y_pred_history = zeros(1,size(macierz_cen, 1));

x_loop = [];
P_loop = [];

Q_final = [];
R_final = 0;
Q_tymczasowy = zeros(liczba_komponentow+1, liczba_komponentow+1, 20);
R_tymczasowy = zeros(1, 20);
LL_tymczasowy = zeros(1, 20);
LL_final = -inf;


clear KalmanSlidingWindow1234;

for i = okno_EM_PCA*2:size(macierz_cen, 1)
    
    syntetyczne_ceny(:,i) = syntetyczne_ceny(:,i-1) + wektory_wlasne' * (log(macierz_cen(i,:)) - log(macierz_cen(i-1,:)))';

    if not(mod(i,czestotliwosc_PCA_EM))
        poolobj = gcp('nocreate');
        if isempty(poolobj)
            disp('Uruchamianie puli równoległej po raz pierwszy...');
            parpool('local', 'IdleTimeout', Inf);
        end

        [~,wektory_wlasne] = PCA(macierz_cen(i-okno_EM_PCA:i,:), liczba_komponentow, wektory_wlasne);

        for j = 1:okno_EM_PCA-okno_MLR
            X_OLS = [ones(okno_MLR, 1) syntetyczne_ceny(:,i-okno_EM_PCA+j:i-okno_EM_PCA+j+okno_MLR-1)'];
            beta_okno(:,j) = (X_OLS'*X_OLS)\X_OLS'*log_waluta_estymowana(i-okno_EM_PCA+j:i-okno_EM_PCA+j+okno_MLR-1);
    
            innowacje_okno = log_waluta_estymowana(i-okno_EM_PCA+j:i-okno_EM_PCA+j+okno_MLR-1) - X_OLS*beta_okno(:,j);
            innowacje_wariancja(j) = var(innowacje_okno);
        end

        R_start = mean(innowacje_wariancja); 
            
        beta_wariancja = var(diff(beta_okno'),0,1);
        Q_start = diag(beta_wariancja);

        okno_syntetyczne_ceny = syntetyczne_ceny(:,i-okno_EM_PCA+1:i)';
        okno_log_waluta_estymowana = log_waluta_estymowana(i-okno_EM_PCA+1:i);

        parfor k = 1:20
            
            Q_0 = Q_start*(rand + 0.5);
            R_0 = R_start*(rand + 0.5);

            [Q_tymczasowy(:, :, k), R_tymczasowy(k), LL_tymczasowy(k)] = EM(A_wej,Q_0,R_0,okno_syntetyczne_ceny,okno_log_waluta_estymowana);
            %fprintf('losowanie %d\n', i);
            %waitbar(i/100, f, sprintf('losowanie: %d/100', i));
        end
       
        %close(f);
        LL_final=-inf;
        LL_final1=-inf;
        
        Q_final = Q_start; 
        R_final = R_start;

        for j = 1:20
                if LL_tymczasowy(j) > LL_final
                    LL_final = LL_tymczasowy(j);
                    Q_final = Q_tymczasowy(:, :, j);
                    R_final = R_tymczasowy(j);
                end
        end
        
        Q1 = Q_final;
        R1 = R_final;
    end

    H_wej = [1 syntetyczne_ceny(:,i)'];

    if isempty(x_loop)
        x_loop = zeros(liczba_komponentow+1, 1);
        P_loop = eye(liczba_komponentow+1);
    end

    [z_score_history(i), spread_history(i), y_pred_history(i), x_history(:,i), P_loop] = KalmanSlidingWindow1234(A_wej, H_wej, Q1, R1, x_loop, P_loop, log_waluta_estymowana(i));
    x_loop = x_history(:,i);

    if mod(i,100) == 0
        fprintf('\rAktualna wartość: %d', i);
    end
end

delete(gcp('nocreate'));

h_eg = zeros(1,size(macierz_cen, 1));

for i = okno_EM_PCA:size(macierz_cen, 1)
    h_eg(i) = adftest(spread_history(i-okno_EM_PCA+1:i));
    if mod(i,100) == 0
        fprintf('\rAktualna wartość: %d', i);
    end
end
