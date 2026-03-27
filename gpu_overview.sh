#!/bin/bash

# Function to get GPU usage for a specific partition and job type
get_gpu_usage() {
    local partition=$1
    local job_type=$2
    
    squeue_output=$(squeue -p $partition | grep $job_type)
    
    echo "========= GPU usage ($partition - $job_type) ========="
    echo "$squeue_output" | awk '
    $7 == "R" {
        # Get username and GPU count
        user = $5
        match($0, /gpu:[0-9]+/)
        gpu = substr($0, RSTART+4, RLENGTH-4)
        if (gpu == "") gpu = 0

        # Accumulate GPU usage per user
        user_gpu[user] += gpu
        total_gpu += gpu
    }
    END {
        # Print GPU usage per user
        for (user in user_gpu) {
            print user ": " user_gpu[user]
        }
        # Print total GPU usage
        print "Total GPU: " total_gpu
    }'
}

# Check GPU usage for both partitions and job types
get_gpu_usage "eb3d_t" "reserved"
echo
get_gpu_usage "eb3d_t" "spot"
echo

