[PL]
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

Wszystko co znajduje się w tym projekcie zostało napisane, przeze mnie samodzielnie. Jedynym wyjątkiem są fragmenty kodu odpowiedzialne za wczytywanie danych z plików zewnętrznych, które zostały wygenerowane przez AI.

[ENG]
​Pairs Trading Strategy Backtest (Kalman Filter vs. Rolling OLS)

​The project contains a set of MATLAB scripts designed to test and optimize a trading strategy on the ETH/BTC pair. The core of the system is an adaptive Kalman filter optimized using the Expectation-Maximization (EM) algorithm, whose results are benchmarked against classic rolling linear regression.
​Project Files

​walk_forward.m – The main script conducting Walk-Forward testing on 5-minute candles. It relies on a Kalman filter combined with a linear regression model. The filter matrices are optimized using the EM algorithm and Kalman Smoother over a 7-day lookback window, updated every 2 days. The input signal requires confirmed cointegration from the past 7 days and a specific entry threshold (calibrated every 0.3 years using data from the preceding 0.7 years). The script compares this method with a 7-day Rolling OLS model.

​bot_adaptacyjny_v1.m – A script calculating all necessary vectors to run the Kalman filter backtest.
​rolling_OLS.m – A script calculating all necessary vectors to run the Rolling OLS backtest.

​liczenieQIR_zwykly.m – An earlier version of the project. It includes a set of statistical tests for normalized Kalman filter innovations (Ljung-Box test, QQ-plot, ACF function). This is used to verify if the innovations behave as white noise and to evaluate the shape of the normalized spread distribution.

​rollingOLS_vs_kalman.m – An older script directly comparing the results of the OLS model and the Kalman filter.
​Data Archives

​rolling_OLS_3year.zip – Compressed files containing pre-calculated parameters for the OLS model.

​adaptacyjny_freq_2day_3year.zip – Compressed files containing recalculated parameters for the adaptive filter (updated every 2 days) spanning a 3-year period.

​Results Status

​Currently, the system demonstrates a clear advantage of the Kalman filter over simple linear regression; however, it encounters limitations related to transaction costs.

​In a theoretical environment (zero commissions), the strategy generates consistent profits.

​After accounting for actual market commissions, the Kalman filter-based system breaks roughly even, whereas the Rolling OLS model loses capital.

​Areas for Improvement and Development

​Implementing and testing alternative models to linear regression within the Kalman filter architecture, such as ARMA or the Ornstein-Uhlenbeck process.

​Identifying and selecting asset pairs with a higher degree of cointegration.

​Incorporating slippage into the backtests to make the simulations more realistic.

​Conducting a deeper investigation and optimization of the Kalman filter innovations.

​Selected References
​https://portfoliooptimizationbook.com/book/
​https://dsstoffer.github.io/files/em.pdf
​https://www.mimuw.edu.pl/~noble/courses/TimeSeries/RESOURCES/ShumwayStofferTimeSeries.pdf
​https://web.mit.edu/kirtley/kirtley/binlustuff/literature/control/Kalman%20filter.pdf

​Authorship
​Everything in this project was written independently by me. The only exception is the code snippets responsible for loading data from external files, which were generated using AI.

