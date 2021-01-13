#!/usr/bin/env bash

## . /root/keystonerc_admin
. /home/astute/keystonerc_yuanjk

BACKUP_VMS=(3b771842-b16b-4272-a9f7-c02531840763)
BACKUP_DIR="/backup_008/tryit/" 
RBD_POOL="openstack-pool"
COPY=2

TODAY=$(date +"%F")


function cleanup() {
    vol_img_id=$1
    all_matched=$(find $BACKUP_DIR -name "${vol_img_id}*" -exec ls -t {} \;)
    count=$(echo $all_matched | awk '{print NF}')
    echo "Remove outdated backups..."
    if [[ $count -gt $COPY ]];then
        echo $all_matched | awk '{for(i=1;i<NF-1;i++) print $i}' | xargs -i echo "Remove {}"
        echo $all_matched | awk '{for(i=1;i<NF-1;i++) print $i}' | xargs -i rm -f {}
    fi
}

function backup() {
    backup_vm=$1
    echo "Backup vm $backup_vm start at $(date +'%F %T')."
    if [[ "${BACKUP_DIR}x" != "x" ]];then
        echo "Create backup dir for vm: $backup_vm"
        mkdir -p ${BACKUP_DIR}/$backup_vm
    fi
    # For the sake of security, stop it at first
    echo "Suspend VM $backup_vm."
    openstack server suspend $backup_vm
    # while :;do
    #     sleep 5
    #     vm_state=$(openstack server show $backup_vm -f json | grep vm_state | awk -F'"' '{print $4}')
    #     power_state=$(openstack server show $backup_vm -f json | grep power_state | awk -F'"' '{print $4}')
    #     [[ $vm_state == "stopped"  && $power_state == "Shutdown" ]] && echo "Virtual machine has stopped.";break
    # done

    # At most how many volumes attached?
    volumes=$(openstack server show $backup_vm -f json | grep volumes_attached | awk -F"'" '{print $2,$4,$6,$8}')
    # Create snapshot
    for vol in $(echo $volumes);do
        ## openstack volume show $vol
        rbd info $RBD_POOL/volume-$vol
        if [[ $? -ne 0 ]];then
            echo "Volume not found: volume-$vol."
            continue
        else
            snap=$RBD_POOL/volume-${vol}@snap_$TODAY
            echo "Create snap $snap."
            rbd snap create $snap
        fi
    done

    openstack server resume $backup_vm
    echo "Resume VM $backup_vm."

    echo "Backup start ..."
    for vol in $(echo $volumes);do
        cleanup volume-$vol
        snap=$RBD_POOL/volume-${vol}@snap_$TODAY
        file=$BACKUP_DIR/$backup_vm/volume-$vol.$TODAY
        if [[ "${BACKUP_DIR}x" != "x" ]];then
            echo "Exporting snap $snap to $file..."
            rbd export $snap $file
            echo "Done."
            [[ $? -ne 0 ]] && echo "Export to $file failed."
            echo "Remove snap $snap."
            rbd snap rm $snap
        fi
    done

    echo "Backup vm $backup_vm complete at $(date +'%F %T')."
}

date "+%F %T"
for backup_vm in ${BACKUP_VMS[@]};do
    backup $backup_vm &
done
date "+%F %T"
