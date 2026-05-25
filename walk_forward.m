
sciezka_do_folderu = 'C:\Users\filip\Documents\adaptacyjny_freq_2day_3year';
lista_plikow = dir(fullfile(sciezka_do_folderu, '*.mat'));

for i = 1:length(lista_plikow)
    pelna_sciezka = fullfile(sciezka_do_folderu, lista_plikow(i).name);
    load(pelna_sciezka);
end

sciezka_do_folderu = 'C:\Users\filip\Documents\rolling_OLS_3year'; 
lista_plikow = dir(fullfile(sciezka_do_folderu, '*.mat'));

for i = 1:length(lista_plikow)
    pelna_sciezka = fullfile(sciezka_do_folderu, lista_plikow(i).name);
    load(pelna_sciezka);
end



%zmiana zależności na B od A
%A to BTC, B to ETH
%BTC = ETH * beta + alfa
%{
temp = aktywo_A;
aktywo_A = aktywo_B;
aktywo_B = temp;

temp1 = aktywo_A1;
aktywo_A1 = aktywo_B1;
aktywo_B1 = temp1;
%}
%modelowanie zależności A od B działa lepiej, możliwe że to przez lead lag

function [s_best, kapital_max_history] = in_sample(z_score_glowny, z_score_dodatkowy, beta_glowna, aktywo_zalezne, aktywo_niezalezne, kointegracja, kapital_start, z_score_range)
    eth_obstawione = 0;
    cena_eth_w_momencie_obstawiania = 0;
    cena_btc_w_momencie_obstawiania = 0;
    btc_obstawione = 0;
    zscore2 = false;
    zscoreneg2 = false;
    ilosc_tranzakcji = 0;
    kapital = kapital_start;
    tranzakcja = false;
    kapital_s = zeros(1000, length(aktywo_zalezne));
    s = zeros(1,1000);

    for k = 1:1000
        s(k) = k*z_score_range/1000;
        eth_obstawione = 0;
        cena_eth_w_momencie_obstawiania = 0;
        cena_btc_w_momencie_obstawiania = 0;
        btc_obstawione = 0;
        zscore2 = false;
        zscoreneg2 = false;
        ilosc_tranzakcji = 0;
        kapital = kapital_start;
        tranzakcja = false;
        for i = 1:length(z_score_glowny)
        
            if tranzakcja == false && kointegracja(i)
                
                if z_score_glowny(i) > s(k) && z_score_dodatkowy(i) < -s(k)  % sprawdzenie czy wyniki kalmanów są mniej więcej takie same, na razie jest tylko jeden, jeszcze nwm czy to będzie dawało jakiekolwiek efekty
                    [ilosc_eth, ilosc_btc] = CalculatePositionSize(kapital, aktywo_zalezne(i), aktywo_niezalezne(i), beta_glowna(i));
                    tranzakcja = true;
                    eth_obstawione = aktywo_zalezne(i)*ilosc_eth;
                    btc_obstawione = aktywo_niezalezne(i)*ilosc_btc;
                    cena_eth_w_momencie_obstawiania = aktywo_zalezne(i);
                    cena_btc_w_momencie_obstawiania = aktywo_niezalezne(i);
                    zscore2 = true;
                elseif z_score_glowny(i) < -s(k) && z_score_dodatkowy(i) > s(k) 
                    [ilosc_eth, ilosc_btc] = CalculatePositionSize(kapital, aktywo_zalezne(i), aktywo_niezalezne(i), beta_glowna(i));
                    tranzakcja = true;
                    eth_obstawione = aktywo_zalezne(i)*ilosc_eth;
                    btc_obstawione = aktywo_niezalezne(i)*ilosc_btc;
                    cena_eth_w_momencie_obstawiania = aktywo_zalezne(i);
                    cena_btc_w_momencie_obstawiania = aktywo_niezalezne(i);
                    zscoreneg2 = true;
                end
            else
                if zscore2 == true
                    if z_score_glowny(i) < 0 && z_score_dodatkowy(i) > 0 %sprawdzanie czy wyniki kalmanów są takie same 
                        zscore2 = false;
                        tranzakcja = false;
                        kapital = kapital + (cena_eth_w_momencie_obstawiania-aktywo_zalezne(i))*eth_obstawione/cena_eth_w_momencie_obstawiania - (cena_btc_w_momencie_obstawiania-aktywo_niezalezne(i))*btc_obstawione/cena_btc_w_momencie_obstawiania;% - 2*eth_obstawione*0.0005 - 2*btc_obstawione*0.0005; %prowizja
                        ilosc_tranzakcji = ilosc_tranzakcji + 1;
                    end
                elseif zscoreneg2 == true
                    if z_score_glowny(i) > 0 && z_score_dodatkowy(i) < 0 %
                        zscoreneg2 = false;
                        tranzakcja = false;
                        kapital = kapital + (aktywo_zalezne(i)-cena_eth_w_momencie_obstawiania)*eth_obstawione/cena_eth_w_momencie_obstawiania - (aktywo_niezalezne(i)-cena_btc_w_momencie_obstawiania)*btc_obstawione/cena_btc_w_momencie_obstawiania;% - 2*eth_obstawione*0.0005 - 2*btc_obstawione*0.0005; %prowizja
                        ilosc_tranzakcji = ilosc_tranzakcji + 1;
                    end
                end
            end
            kapital_s(k,i) = kapital;
        end
    end
    
    kapital_max = 0;
    indeks = 0;
    
    for i = 1:1000
        if kapital_s(i,length(aktywo_zalezne)) > kapital_max
            kapital_max = kapital_s(i,length(aktywo_zalezne));
            indeks = i;
        end
    end
    kapital_max_history = kapital_s(indeks,:);
    s_best = s(indeks);
end

function [kapital_history] = out_of_sample(z_score_glowny, z_score_dodatkowy, beta_glowna, aktywo_zalezne, aktywo_niezalezne, kointegracja, kapital_start,  prog)

    kapital_s = zeros(1, length(aktywo_zalezne));
    eth_obstawione = 0;
    cena_eth_w_momencie_obstawiania = 0;
    cena_btc_w_momencie_obstawiania = 0;
    btc_obstawione = 0;
    zscore2 = false;
    zscoreneg2 = false;
    ilosc_tranzakcji = 0;
    kapital = kapital_start;
    tranzakcja = false;

    for i = 1:length(z_score_glowny)
    
        if tranzakcja == false && kointegracja(i)
            
            if z_score_glowny(i) > prog && z_score_dodatkowy(i) < -prog  % sprawdzenie czy wyniki kalmanów są mniej więcej takie same, na razie jest tylko jeden, jeszcze nwm czy to będzie dawało jakiekolwiek efekty
                [ilosc_eth, ilosc_btc] = CalculatePositionSize(kapital, aktywo_zalezne(i), aktywo_niezalezne(i), beta_glowna(i));
                tranzakcja = true;
                eth_obstawione = aktywo_zalezne(i)*ilosc_eth;
                btc_obstawione = aktywo_niezalezne(i)*ilosc_btc;
                cena_eth_w_momencie_obstawiania = aktywo_zalezne(i);
                cena_btc_w_momencie_obstawiania = aktywo_niezalezne(i);
                zscore2 = true;
            elseif z_score_glowny(i) < -prog && z_score_dodatkowy(i) > prog 
                [ilosc_eth, ilosc_btc] = CalculatePositionSize(kapital, aktywo_zalezne(i), aktywo_niezalezne(i), beta_glowna(i));
                tranzakcja = true;
                eth_obstawione = aktywo_zalezne(i)*ilosc_eth;
                btc_obstawione = aktywo_niezalezne(i)*ilosc_btc;
                cena_eth_w_momencie_obstawiania = aktywo_zalezne(i);
                cena_btc_w_momencie_obstawiania = aktywo_niezalezne(i);
                zscoreneg2 = true;
            end
        else
            if zscore2 == true
                if z_score_glowny(i) < 0 && z_score_dodatkowy(i) > 0 %sprawdzanie czy wyniki kalmanów są takie same 
                    zscore2 = false;
                    tranzakcja = false;
                    kapital = kapital + (cena_eth_w_momencie_obstawiania-aktywo_zalezne(i))*eth_obstawione/cena_eth_w_momencie_obstawiania - (cena_btc_w_momencie_obstawiania-aktywo_niezalezne(i))*btc_obstawione/cena_btc_w_momencie_obstawiania;% - 2*eth_obstawione*0.0005 - 2*btc_obstawione*0.0005; %prowizja
                    ilosc_tranzakcji = ilosc_tranzakcji + 1;
                end
            elseif zscoreneg2 == true
                if z_score_glowny(i) > 0 && z_score_dodatkowy(i) < 0 %
                    zscoreneg2 = false;
                    tranzakcja = false;
                    kapital = kapital + (aktywo_zalezne(i)-cena_eth_w_momencie_obstawiania)*eth_obstawione/cena_eth_w_momencie_obstawiania - (aktywo_niezalezne(i)-cena_btc_w_momencie_obstawiania)*btc_obstawione/cena_btc_w_momencie_obstawiania;% - 2*eth_obstawione*0.0005 - 2*btc_obstawione*0.0005; %prowizja
                    ilosc_tranzakcji = ilosc_tranzakcji + 1;
                end
            end
        end
        kapital_s(i) = kapital;
    end

    kapital_history = kapital_s;

end


h_lbq = zeros(1,52);
h_eg_avg = zeros(1,182);

for i = 1:52 %52 tygodnie w roku
    %zmiana długości wektora próbek do EM ma wpływ na działanie modelu
    %policzone Q i R raczej dobrze opisują model tylko przez 2 dni, więc pewnie będę musiał zmienić częstotliwość liczenia Q i R
    h_lbq(i) = lbqtest(z_score_history((i-1)*288*7+1:i*288*7-288*0)); %dla tego konkretnie modelu spreadu z_score jest tym samym co znormalizowane innowacje
end

for i = 1:182 %znormalizowana liczba próbek których występuje kointegracja dla danych sprzed tygodnia do teraz, w konkretnym tygodniu 
    h_eg_avg(i) = mean(h_eg((i-1)*288*2+1:i*288*2)); 
end

kapital_in_history = zeros(7,floor(length(aktywo_A)*0.7/3)+1);
kapital_out_history = zeros(7,floor(length(aktywo_A)/3) - floor(length(aktywo_A)*0.7/3) + 1);
s_history = zeros(1,7);

kapital_out_of_sample = 10000;

kapital_in_historyOLS = zeros(7,floor(length(aktywo_A)*0.7/3)+1);
kapital_out_historyOLS = zeros(7,floor(length(aktywo_A)/3) - floor(length(aktywo_A)*0.7/3) + 1);
s_historyOLS = zeros(1,7);

kapital_out_of_sampleOLS = 10000;

for i = 0:6
    z_score_glowny_in_sample = z_score_history(288*7 + i*floor(length(aktywo_A)*0.3/3):288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)*0.7/3));
    z_score_glowny_out_of_sample = z_score_history(288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)*0.7/3):288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)/3));
    z_score_dodatkowy_in_sample = z_score_history1(288*7 + i*floor(length(aktywo_A)*0.3/3):288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)*0.7/3));
    z_score_dodatkowy_out_of_sample = z_score_history1(288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)*0.7/3):288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)/3));
    beta_glowna_in_sample = beta_history(288*7 + i*floor(length(aktywo_A)*0.3/3):288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)*0.7/3));
    beta_glowna_out_of_sample = beta_history(288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)*0.7/3):288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)/3));
    aktywo_zalezne_in_sample = aktywo_A1(288*7 + i*floor(length(aktywo_A)*0.3/3):288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)*0.7/3));
    aktywo_zalezne_out_of_sample = aktywo_A1(288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)*0.7/3):288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)/3));
    aktywo_niezalezne_in_sample = aktywo_B1(288*7 + i*floor(length(aktywo_A)*0.3/3):288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)*0.7/3));
    aktywo_niezalezne_out_of_sample = aktywo_B1(288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)*0.7/3):288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)/3));

    z_score_glowny_in_sampleOLS = z_score1(288*7 + i*floor(length(aktywo_A)*0.3/3):288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)*0.7/3));
    z_score_glowny_out_of_sampleOLS = z_score1(288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)*0.7/3):288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)/3));
    z_score_dodatkowy_in_sampleOLS = z_score2(288*7 + i*floor(length(aktywo_A)*0.3/3):288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)*0.7/3));
    z_score_dodatkowy_out_of_sampleOLS = z_score2(288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)*0.7/3):288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)/3));
    beta_glowna_in_sampleOLS = beta_historyOLS1(288*7 + i*floor(length(aktywo_A)*0.3/3):288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)*0.7/3));
    beta_glowna_out_of_sampleOLS = beta_historyOLS1(288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)*0.7/3):288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)/3));

    [s_history(i+1), kapital_in_history(i+1,:)] = in_sample(z_score_glowny_in_sample, z_score_dodatkowy_in_sample, beta_glowna_in_sample, aktywo_zalezne_in_sample, aktywo_niezalezne_in_sample, h_eg, 10000, 1);
    kapital_out_history(i+1,:) = out_of_sample(z_score_glowny_out_of_sample, z_score_dodatkowy_out_of_sample, beta_glowna_out_of_sample, aktywo_zalezne_out_of_sample, aktywo_niezalezne_out_of_sample, h_eg, kapital_out_of_sample, s_history(i+1));
    kapital_out_of_sample = kapital_out_history(i+1,end);

    [s_historyOLS(i+1), kapital_in_historyOLS(i+1,:)] = in_sample(z_score_glowny_in_sampleOLS, z_score_dodatkowy_in_sampleOLS, beta_glowna_in_sampleOLS, aktywo_zalezne_in_sample, aktywo_niezalezne_in_sample, h_eg, 10000, 5);
    kapital_out_historyOLS(i+1,:) = out_of_sample(z_score_glowny_out_of_sampleOLS, z_score_dodatkowy_out_of_sampleOLS, beta_glowna_out_of_sampleOLS, aktywo_zalezne_out_of_sample, aktywo_niezalezne_out_of_sample, h_eg, kapital_out_of_sampleOLS, s_historyOLS(i+1));
    kapital_out_of_sampleOLS = kapital_out_historyOLS(i+1,end);
end

for i = 0:6
    figure();
    subplot(2,1,1); plot(time_axis(288*7 + i*floor(length(aktywo_A)*0.3/3):288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)*0.7/3)), kapital_in_history(i+1,:), 'b');
    subplot(2,1,2);plot(time_axis(288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)*0.7/3):288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)/3)), kapital_out_history(i+1,:), 'g');
end

for i = 0:6
    figure();
    subplot(2,1,1); plot(time_axis(288*7 + i*floor(length(aktywo_A)*0.3/3):288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)*0.7/3)), kapital_in_historyOLS(i+1,:), 'b');
    subplot(2,1,2);plot(time_axis(288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)*0.7/3):288*7 + i*floor(length(aktywo_A)*0.3/3) + floor(length(aktywo_A)/3)), kapital_out_historyOLS(i+1,:), 'g');
end

figure();
stem(s_history);
%{
eth_obstawione = 0;
cena_eth_w_momencie_obstawiania = 0;
cena_btc_w_momencie_obstawiania = 0;
btc_obstawione = 0;
zscore2 = false;
zscoreneg2 = false;
kapital_history1 = zeros(1, length(aktywo_A));
ilosc_tranzakcji = 0;
kapital = 10000;
tranzakcja = false;
kapital_s1 = zeros(1000, length(aktywo_A));
s1 = zeros(1,1000);

for k = 1:1000
    s1(k) = 8*k/1000;
    eth_obstawione = 0;
    cena_eth_w_momencie_obstawiania = 0;
    cena_btc_w_momencie_obstawiania = 0;
    btc_obstawione = 0;
    zscore2 = false;
    zscoreneg2 = false;
    ilosc_tranzakcji = 0;
    kapital = 10000;
    tranzakcja = false;

    for i = 277*8:length(z_score1)    
    
        if tranzakcja == false && h_eg(i) 
            
            if z_score1(i) > s1(k)% && z_score(i) < -0.05  % sprawdzenie czy wyniki kalmanów są mniej więcej takie same % && abs(spread_history(i))/y(i) > min_profit
                [ilosc_eth, ilosc_btc] = CalculatePositionSize(kapital, aktywo_A1(i), aktywo_B1(i), beta_historyOLS1(i));
                tranzakcja = true;
                eth_obstawione = aktywo_A1(i)*ilosc_eth;
                btc_obstawione = aktywo_B1(i)*ilosc_btc;
                cena_eth_w_momencie_obstawiania = aktywo_A1(i);
                cena_btc_w_momencie_obstawiania = aktywo_B1(i);
                zscore2 = true;
            elseif z_score1(i) < -s1(k)% && z_score(i) > 0.05 %&& abs(spread_history(i))/y(i) > min_profit
                [ilosc_eth, ilosc_btc] = CalculatePositionSize(kapital, aktywo_A1(i), aktywo_B1(i), beta_historyOLS1(i));
                tranzakcja = true;
                eth_obstawione = aktywo_A1(i)*ilosc_eth;
                btc_obstawione = aktywo_B1(i)*ilosc_btc;
                cena_eth_w_momencie_obstawiania = aktywo_A1(i);
                cena_btc_w_momencie_obstawiania = aktywo_B1(i);
                zscoreneg2 = true;
            end
        else
            if zscore2 == true
                if z_score1(i) < 0 %&& (cena_eth_w_momencie_obstawiania-y(i))*eth_obstawione/cena_eth_w_momencie_obstawiania - (cena_btc_w_momencie_obstawiania-x(i))*btc_obstawione/cena_btc_w_momencie_obstawiania - 2*eth_obstawione*0.0005 - 2*btc_obstawione*0.0005 > 0
                    zscore2 = false;
                    tranzakcja = false;
                    kapital = kapital + (cena_eth_w_momencie_obstawiania-aktywo_A1(i))*eth_obstawione/cena_eth_w_momencie_obstawiania - (cena_btc_w_momencie_obstawiania-aktywo_B1(i))*btc_obstawione/cena_btc_w_momencie_obstawiania;% - 2*eth_obstawione*0.0005 - 2*btc_obstawione*0.0005; %prowizja
                    ilosc_tranzakcji = ilosc_tranzakcji + 1;
                end
            elseif zscoreneg2 == true
                if z_score1(i) > 0 %&& (y(i)-cena_eth_w_momencie_obstawiania)*eth_obstawione/cena_eth_w_momencie_obstawiania - (x(i)-cena_btc_w_momencie_obstawiania)*btc_obstawione/cena_btc_w_momencie_obstawiania - 2*eth_obstawione*0.0005 - 2*btc_obstawione*0.0005 > 0
                    zscoreneg2 = false;
                    tranzakcja = false;
                    kapital = kapital + (aktywo_A1(i)-cena_eth_w_momencie_obstawiania)*eth_obstawione/cena_eth_w_momencie_obstawiania - (aktywo_B1(i)-cena_btc_w_momencie_obstawiania)*btc_obstawione/cena_btc_w_momencie_obstawiania;% - 2*eth_obstawione*0.0005 - 2*btc_obstawione*0.0005; %prowizja
                    ilosc_tranzakcji = ilosc_tranzakcji + 1;
                end
            end
        end
        kapital_s1(k,i) = kapital;
    end
end

kapital_max1 = 0;
indeks1 = 0;

for i = 1:1000
    if kapital_s1(i,length(aktywo_A)) > kapital_max1
        kapital_max1 = kapital_s1(i,length(aktywo_A));
        indeks1 = i;
    end
end
%}
function [qty_eth, qty_btc] = CalculatePositionSize(capital_usd, price_eth, price_btc, beta)

    allocation_eth = capital_usd / (1 + beta); 
    allocation_btc = capital_usd - allocation_eth;
    
    qty_eth = allocation_eth / price_eth;
    qty_btc = allocation_btc / price_btc; 
    
end