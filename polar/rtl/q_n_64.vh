// 5G NR TS 38.212 Table 5.3.1.2-1 Polar reliability sequence Q_N
// N=64, Q_N[0]=least reliable, Q_N[63]=most reliable
// Subsampled from Q_1024 master sequence (keep elements < N)

localparam integer POLAR_N = 64;
localparam integer POLAR_LOG2N = 6;
localparam [6:0] Q_N [0:63] = '{
    0, 1, 2, 4, 8, 16, 32, 3,
    5, 9, 6, 17, 10, 18, 12, 33,
    20, 34, 24, 36, 7, 11, 40, 19,
    13, 48, 14, 21, 35, 26, 37, 25,
    22, 38, 41, 28, 42, 49, 44, 50,
    15, 52, 23, 56, 27, 39, 29, 43,
    30, 45, 51, 46, 53, 54, 57, 58,
    60, 31, 47, 55, 59, 61, 62, 63
};
