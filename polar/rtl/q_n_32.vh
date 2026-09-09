// 5G NR TS 38.212 Table 5.3.1.2-1 Polar reliability sequence Q_N
// N=32, Q_N[0]=least reliable, Q_N[31]=most reliable
// Subsampled from Q_1024 master sequence (keep elements < N)

localparam integer POLAR_N = 32;
localparam integer POLAR_LOG2N = 5;
localparam [5:0] Q_N [0:31] = '{
    0, 1, 2, 4, 8, 16, 3, 5,
    9, 6, 17, 10, 18, 12, 20, 24,
    7, 11, 19, 13, 14, 21, 26, 25,
    22, 28, 15, 23, 27, 29, 30, 31
};
