# Compilers and Flags
CC       := gcc
CXX      := g++
CFLAGS   := -std=c11 -Wall -Wextra -O3 -MMD -MP
CXXFLAGS := -std=c++17 -Wall -Wextra -O3 -MMD -MP
INCLUDES := -Iinclude -Isrc

# Build Directories and Target
SRC_DIR   := src
BUILD_DIR := build
TARGET    := $(BUILD_DIR)/main

# Find all C and C++ source files in SRC_DIR
C_SRCS   := $(wildcard $(SRC_DIR)/*.c)
CXX_SRCS := $(wildcard $(SRC_DIR)/*.cpp)

# Map source files to object files in BUILD_DIR
C_OBJS   := $(patsubst $(SRC_DIR)/%.c, $(BUILD_DIR)/%.o, $(C_SRCS))
CXX_OBJS := $(patsubst $(SRC_DIR)/%.cpp, $(BUILD_DIR)/%.o, $(CXX_SRCS))
OBJS     := $(C_OBJS) $(CXX_OBJS)

# Dependency files for auto-header tracking
DEPS     := $(OBJS:.o=.d)

# Default Rule
all: $(TARGET)

# Link Object Files into the Executable using g++
$(TARGET): $(OBJS)
	@mkdir -p $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(OBJS) -o $@
	@echo "Build complete: $@"

# Rule for C Source Files
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

# Rule for C++ Source Files
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.cpp
	@mkdir -p $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c $< -o $@

# Include generated header dependency rules
-include $(DEPS)

compress:
	@echo "Compressing .tri files in assets/ larger than 50MB..."
	@find assets -type f -name "*.tri" -size +50M -exec gzip -v9 {} +

uncompress:
	@echo "Decompressing .tri.gz files in assets/..."
	@find assets -type f -name "*.tri.gz" -exec gunzip -v {} +

# Clean up build artifacts
clean:
	rm -rf $(BUILD_DIR)

# Run the golden model
run: $(TARGET)
	./$(TARGET)

.PHONY: all clean run