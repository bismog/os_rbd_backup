#!/usr/bin/env bash

. /root/keystonerc_admin

# VM uuid
BACKUP_VMS=(xxxx-1111 xxxx-2222 xxxx-3333)
# Backup directory, mount from external storage
BACKUP_STORE="/vm_backup/" 
# CEPH RBD pool
RBD_POOL="xj-pool"
# Keep at least x copies
COPY=2

TODAY=$(date +"%F")


function cleanup() {
    vol_img_id=$1
    all_matched=$(find $BACKUP_STORE -name "${vol_img_id}*" -exec ls -t {} \;)
    count=$(echo $all_matched | awk '{print NF}')
    echo "Remove outdated backups..."
    if [[ $count -gt $COPY ]];then
        echo $all_matched | awk '{for(i=1;i<NF-1;i++) print $i}' | xargs -i echo "Remove {}"
        echo $all_matched | awk '{for(i=1;i<NF-1;i++) print $i}' | xargs -i rm -f {}
    fi
}

function backup() {
    backup_vm=$1
    echo "Backup vm $backup_vm start at $(date +'%F %T')"
    if [[ "${BACKUP_STORE}x" != "x" ]];then
        echo "Create backup1 dir for vm: $backup_vm"
        mkdir -p ${BACKUP_STORE}/$backup_vm
    fi
    # For the sake of security, stop it at first
    echo "Try stopping the virtual machine..."
    openstack server stop $backup_vm;
    while :;do
        sleep 5
        vm_state=$(openstack server show $backup_vm -f json | grep vm_state | awk -F'"' '{print $4}')
        power_state=$(openstack server show $backup_vm -f json | grep power_state | awk -F'"' '{print $4}')
        [[ $vm_state == "stopped"  && $power_state == "Shutdown" ]] && echo "Virtual machine has stopped.";break
    done

    echo "Backup start ..."
    # At most how many volumes attached?
    volumes=$(openstack server show $backup_vm -f json | grep volumes_attached | awk -F"'" '{print $2,$4,$6,$8}')
    for vol in $(echo $volumes);do
        openstack volume show $vol
        rbd -p $RBD_POOL info volume-$vol
        if [[ $? -ne 0 ]];then
            echo "Volume not found: volume-$vol"
            continue
        else
            cleanup volume-$vol
            if [[ "${BACKUP_STORE}x" != "x" ]];then
                echo "Exporting to $BACKUP_STORE/$backup_vm ..."
                rbd -p $RBD_POOL export volume-$vol $BACKUP_STORE/$backup_vm/volume-$vol.$TODAY
                [[ $? -ne 0 ]] && echo "Export to backup1 failed."
            fi
        fi
    done

    openstack server start $backup_vm
    echo "Virtual machine started."
    echo "Done."
    echo "Backup vm $backup_vm complete at $(date +'%F %T')"
}

date "+%F %T"
for backup_vm in ${BACKUP_VMS[@]};do
    backup $backup_vm &
done
date "+%F %T"
