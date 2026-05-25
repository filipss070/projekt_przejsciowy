Backtest strategii Pairs Trading (Filtr Kalmana vs Rolling OLS)
Projekt zawiera zbiór skryptów w środowisku MATLAB służących do testowania i optymalizacji strategii na parze ETH i BTC. Rdzeniem systemu jest adaptacyjny filtr Kalmana optymalizowany algorytmem EM, którego wyniki są zestawiane z klasyczną regresją kroczącą.

Pliki projektowe
-walk_forward.m - Główny skrypt przeprowadzający test Walk-Forward na 5-minutowych świecach. Oparty na filtrze Kalmana z modelem regresji liniowej. Macierze filtru są optymalizowane przy użyciu algorytmu EM i Kalman Smoothera na 7-dniowym oknie wstecz, z aktualizacją co 2 dni. Sygnał wejściowy wymaga potwierdzonej kointegracji z ostatnich 7 dni oraz odpowiedniego progu wejścia (kalibrowanego co 0.3 roku na danych z poprzednich 0.7 roku). Skrypt porównuje tę metodę z 7-dniowym modelem kroczącym OLS.

-bot_adaptacyjny_v1.m - Skrypt obliczający wszystkie wektory potrzebne do przeprowadzenia backtestu dla filtru Kalmana.

-rolling_OLS.m - Skrypt obliczający wszystkie wektory potrzebne do przeprowadzenia backtestu dla rolling OLS.

-liczenieQIR_zwykly.m - Wcześniejsza wersja projektu. Zawiera zestaw testów statystycznych dla znormalizowanych innowacji filtru Kalmana (test Ljung-Boxa, QQ-plot, funkcja ACF). Służy do weryfikacji, czy innowacje są szumem białym oraz pozwala ocenić kształt rozkładu znormalizowanego spreadu.

-rollingOLS_vs_kalman.m - Starsza wersja skryptu porównującego bezpośrednio wyniki modelu OLS oraz filtru Kalmana.

Archiwa z danymi
-rolling_OLS_3year.zip - Skompresowane pliki z gotowymi parametrami dla modelu OLS.

-adaptacyjny_freq_2day_3year.zip - Skompresowane pliki z przeliczonymi parametrami dla filtru adaptacyjnego (z odświeżaniem co 2 dni) z okresu 3 lat.

Status wyników
-Obecnie system demonstruje wyraźną przewagę filtru Kalmana nad prostą regresją liniową, jednak napotyka na ograniczenia związane z kosztami transakcyjnymi.

-W środowisku teoretycznym (bez prowizji) strategia generuje zyski.

-Po uwzględnieniu rynkowych prowizji system oparty na filtrze Kalmana wychodzi mniej więcej na zero, podczas gdy model Rolling OLS traci kapitał.

Rzeczy do poprawy i rozwoju
-Wdrożenie i przetestowanie modeli alternatywnych dla regresji liniowej w filtrze Kalmana, takich jak ARMA czy proces Ornsteina-Uhlenbecka.

-Identyfikacja i dobór par aktywów o wyższym stopniu kointegracji.

-Uwzględnienie slippage w backtestach, aby uczynić je jeszcze bardziej realistycznymi.

-Dokładniejsze zbadanie i optymalizacja innowacji samego filtru Kalmana.

Część źródeł z których korzystałem:

https://portfoliooptimizationbook.com/book/

https://dsstoffer.github.io/files/em.pdf

https://www.mimuw.edu.pl/~noble/courses/TimeSeries/RESOURCES/ShumwayStofferTimeSeries.pdf

https://web.mit.edu/kirtley/kirtley/binlustuff/literature/control/Kalman%20filter.pdf

Autorstwo
Wszystkie algorytmy, modele analityczne oraz logika testów zawarte w tym projekcie zostały napisane i zaimplementowane przeze mnie w pełni samodzielnie. Jedynym wyjątkiem są standardowe fragmenty kodu odpowiedzialne za wczytywanie danych z plików zewnętrznych, które zostały wygenerowane przez AI.
