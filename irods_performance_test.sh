#!/bin/bash

# iRODS Performance Test Script
# Tests file upload/download times and calculates averages

# Configuration
TEST_RUNS=25
TEST_FILE_SIZE="100M"  # Size of test file to create
RESULTS_DIR="./performance_results"
TIMESTAMP=$(date -u '+%Y-%m-%d_%H-%M-%S')
CONTAINER_NAME="ubuntu-2204-postgres-14_irods-catalog-provider_1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== iRODS Performance Test ===${NC}"
echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "Test runs: $TEST_RUNS"
echo "Test file size: $TEST_FILE_SIZE"
echo

# Create results directory
mkdir -p "$RESULTS_DIR"

# Check if iRODS container is running
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo -e "${RED}Error: iRODS container is not running!${NC}"
    echo "Please start it first with:"
    echo "python stand_it_up.py --project-directory ./projects/ubuntu-22.04/ubuntu-22.04-postgres-14"
    exit 1
fi

# Check if we can connect to iRODS
if ! docker exec -u irods $CONTAINER_NAME ils >/dev/null 2>&1; then
    echo -e "${RED}Error: Cannot connect to iRODS!${NC}"
    exit 1
fi

# Create a shared directory for file exchange (if it doesn't exist)
docker exec $CONTAINER_NAME mkdir -p /host_data 2>/dev/null

# Function to run performance test
run_performance_test() {
    local test_file="test_file_${TEST_FILE_SIZE}_${RANDOM}.dat"
    local irods_path="/tempZone/home/rods/${test_file}"
    
    echo -e "${YELLOW}Creating test file (${TEST_FILE_SIZE})...${NC}"
    truncate -s$TEST_FILE_SIZE "$test_file"
    
    declare -a upload_times
    declare -a download_times
    
    echo -e "${YELLOW}Running $TEST_RUNS test iterations...${NC}"
    
    for i in $(seq 1 $TEST_RUNS); do
        echo -n "  Run $i/$TEST_RUNS: "
        
        # Test upload (iput)
        echo -n "Upload... "
        upload_start=$(date +%s.%N)
        docker exec -u irods $CONTAINER_NAME \
            bash -c "cd /tmp && iput /host_data/$test_file $irods_path" 2>/dev/null
        upload_end=$(date +%s.%N)
        upload_time=$(echo "$upload_end - $upload_start" | bc -l)
        upload_times+=($upload_time)     
        
        # Test download (iget)
        echo -n "Download... "
        download_start=$(date +%s.%N)
        docker exec -u irods $CONTAINER_NAME \
            bash -c "cd /tmp && iget -f $irods_path /tmp/downloaded_$test_file" 2>/dev/null
        download_end=$(date +%s.%N)
        download_time=$(echo "$download_end - $download_start" | bc -l)
        download_times+=($download_time)
        
        # Clean up iRODS file for next iteration
        docker exec -u irods $CONTAINER_NAME \
            bash -c "irm -f $irods_path" 2>/dev/null
        
        echo -e "${GREEN}Done${NC} (Upload: ${upload_time}s, Download: ${download_time}s)"
    done
    
    # Clean up test file
    rm -f "$test_file"
    
    # Export results for processing
    echo "${upload_times[*]}" > "${RESULTS_DIR}/upload_times_${TIMESTAMP}.txt"
    echo "${download_times[*]}" > "${RESULTS_DIR}/download_times_${TIMESTAMP}.txt"
    
    echo
    echo -e "${GREEN}Raw results saved. Processing results...${NC}"
}

# Run the test
run_performance_test

# Call process_results.sh to calculate and save final results
./process_results.sh "$RESULTS_DIR" "$TIMESTAMP" "$TEST_RUNS" "$TEST_FILE_SIZE" "$CONTAINER_NAME"

echo -e "${GREEN}Performance test completed!${NC}"

