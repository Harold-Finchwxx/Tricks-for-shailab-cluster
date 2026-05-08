#!/bin/bash

# Get the running tasks of the wam_model partition

sacct -a -r wam_model --format=User%15,JobID%15,JobName%10,Partition%10,VirtualPartition%5,QuotaType%19,NNodes,AllocTres%70,AllocCPUS,State,Submit,node%100 | grep RUNNING > tmp.txt
python /mnt/petrelfs/wangxuanxu/tricks-for-cluster/nodelist.py --rawfile tmp.txt
