# FFT Golden Model Makefile
# 编译 C 模型并生成测试向量

CC = gcc
CFLAGS = -O2 -Wall -Wextra
LDFLAGS = -lm

TARGET = fft_model
N ?= 1024

all: $(TARGET)

$(TARGET): fft_model.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

# 生成随机测试输入
gen_input: $(TARGET)
	./$(TARGET) $(N) gen ../tb/data/input_$(N).txt

# 生成正向 FFT 期望输出
gen_fft: $(TARGET) gen_input
	./$(TARGET) $(N) forward ../tb/data/input_$(N).txt ../tb/data/expected_fft_$(N).txt

# 生成反向 FFT 期望输出
gen_ifft: $(TARGET) gen_input
	./$(TARGET) $(N) inverse ../tb/data/input_$(N).txt ../tb/data/expected_ifft_$(N).txt

# 生成全部测试向量
gen_all: gen_fft gen_ifft

clean:
	rm -f $(TARGET) *.o

.PHONY: all gen_input gen_fft gen_ifft gen_all clean
