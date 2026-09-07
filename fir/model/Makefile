# FIR Golden Model Makefile

CC = gcc
CFLAGS = -O2 -Wall -Wextra
LDFLAGS = -lm

TARGET = fir_model
NUM_TAPS ?= 32
CUTOFF ?= 0.25
SYMMETRIC ?= symmetric

all: $(TARGET)

$(TARGET): fir_model.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

# 生成系数（低通，截止频率 0.25*fs，对称）
gen_coeff: $(TARGET)
	./$(TARGET) gen_coeff $(NUM_TAPS) ../tb/data/fir_coeff.mem lowpass $(CUTOFF) $(SYMMETRIC)

# 生成随机输入
gen_input:
	python3 ../scripts/gen_test_input.py --n 2048 --out ../tb/data/fir_input.txt

# 生成期望输出
gen_output: $(TARGET) gen_coeff gen_input
	./$(TARGET) filter $(NUM_TAPS) ../tb/data/fir_coeff.mem ../tb/data/fir_input.txt ../tb/data/fir_expected.txt $(SYMMETRIC)

# 生成全部测试向量
gen_all: gen_output

clean:
	rm -f $(TARGET) *.o

.PHONY: all gen_coeff gen_input gen_output gen_all clean
