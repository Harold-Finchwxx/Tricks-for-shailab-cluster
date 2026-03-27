import argparse

parser = argparse.ArgumentParser()
parser.add_argument('--rawfile', type=str, required=True)
parser.add_argument('--fgpu', action='store_true', default=False)
args = parser.parse_args()

with open(args.rawfile, 'r') as f:
    lines = f.readlines()

node_dict = {}
for line in lines:
    user = line[0:15].strip()
    if user == '':
        continue
    jobid = line[16:31].strip()
    rest_str = [s.strip() for s in line[32:].split(' ') if s.strip()]
    jobname = rest_str[0]
    # partition = rest_str[2]
    quota_type = rest_str[3]
    nnodes = rest_str[4]
    
    alloc_tres = rest_str[5]
    alloc_gpus = 0
    for tres in alloc_tres.split(','):
        if tres.startswith("gres/gpu"):
            alloc_gpus = int(tres.split('=')[1])
    alloc_cpus = rest_str[6]
    alloc_cpu_per_node = int(alloc_cpus) / int(nnodes)
    alloc_gpu_per_node = alloc_gpus / int(nnodes)

    # state = rest_str[7]
    submit_time = rest_str[8]  # such as 2025-05-07T18:01:51
    # calculate duration
    import datetime
    this_time = datetime.datetime.strptime(submit_time, '%Y-%m-%dT%H:%M:%S')
    now_time = datetime.datetime.now()
    duration = now_time - this_time
    
    node_list_str = rest_str[9]
    node_groups = node_list_str.split(',HOST')
    if len(node_groups) > 1:
        for idx in range(1, len(node_groups)):
            node_groups[idx] = 'HOST' + node_groups[idx]
    node_list = []
    # node_groups = [ng.split('-') for ng in node_groups]
    for node_group in node_groups:
        if node_group.endswith(']'):
            no_start = node_group.find('[')
            main_str = node_group[:no_start]
            nos = node_group[no_start+1:-1].split(',')
            for no in nos:
                if '-' in no:
                    nos, noe = no.split('-')
                    for subno in range(int(nos), int(noe) + 1):
                        node_list.append(main_str + str(subno))
                else:
                    node_list.append(main_str + no)
        else:
            node_list.append(node_group)

    for node in node_list:
        if node not in node_dict:
            node_dict[node] = []
        node_dict[node].append((quota_type, jobid, jobname, user, nnodes, alloc_gpu_per_node, alloc_cpu_per_node, duration))

all_reserved_nodes = []
mixed_nodes = []
all_spot_nodes = []

for node, jobs in node_dict.items():
    have_reserved = False
    have_spot = False
    for job in jobs:
        if job[0] == 'reserved':
            have_reserved = True
        else:
            have_spot = True
    if have_reserved and have_spot:
        mixed_nodes.append(node)
    elif have_reserved:
        all_reserved_nodes.append(node)
    elif have_spot:
        all_spot_nodes.append(node)

all_reserved_nodes = sorted(all_reserved_nodes)
all_spot_nodes = sorted(all_spot_nodes)
mixed_nodes = sorted(mixed_nodes)

def output_node_info(gathered_node_list):
    output_dict = {}
    for node in gathered_node_list:
        node_meta = node_dict[node]
        node_cpus, node_gpus = 0, 0
        for job in node_meta:
            quota_type, jobid, jobname, user, nnodes, alloc_gpu_per_node, alloc_cpu_per_node, duration = job
            if abs(alloc_gpu_per_node - int(alloc_gpu_per_node)) > 1e-5:
                print(f"[Warning] {jobid}: {jobname} gpu_per_node {alloc_gpu_per_node} is not an integer")
            if abs(alloc_cpu_per_node - int(alloc_cpu_per_node)) > 1e-5:
                print(f"[Warning] {jobid}: {jobname} cpu_per_node {alloc_cpu_per_node} is not an integer")
            node_cpus += int(alloc_cpu_per_node)
            node_gpus += int(alloc_gpu_per_node)
        output_dict[node] = (node_gpus, node_cpus)

    gathered_node_list = sorted(gathered_node_list, key=lambda x: output_dict[x], reverse=False)
    for node in gathered_node_list:
        node_meta = node_dict[node]
        node_gpus, node_cpus = output_dict[node]
        if args.fgpu and node_gpus == 8:
            continue
        print(f'GPU {node_gpus}/8, CPU {node_cpus:>3}/128(112): {node}')
        for job in node_meta:
            quota_type, jobid, jobname, user, nnodes, alloc_gpu_per_node, alloc_cpu_per_node, duration = job
            print(f'    [{quota_type:<8}] GPU {int(alloc_gpu_per_node):>2}, CPU {int(alloc_cpu_per_node):>3}, USER {user:>12}, [{jobid}: {jobname:>10}], NNODES {nnodes:>2}, DURATION {duration}')
        print()

print(f'---------------------------------------- {"Reserved":<8} Nodes: {len(all_reserved_nodes):>3} ----------------------------------------')
print('-----------------------------------------------------------------------------------------------------')
print()
output_node_info(all_reserved_nodes)
print()

print(f'---------------------------------------- {"Mixed":<8} Nodes: {len(mixed_nodes):>3} ----------------------------------------')
print('-----------------------------------------------------------------------------------------------------')
print()
output_node_info(mixed_nodes)
print()

print(f'---------------------------------------- {"Spot":<8} Nodes: {len(all_spot_nodes):>3} ----------------------------------------')
print('-----------------------------------------------------------------------------------------------------')
print()
output_node_info(all_spot_nodes)
print()

import os
os.remove(args.rawfile)