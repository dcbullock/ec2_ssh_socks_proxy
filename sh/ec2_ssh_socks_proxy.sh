#!/bin/sh


port_default=9443

# set VERBOSE so it can be assumed not empty in further usage
VERBOSE=no

usage()
{
    echo "Usage: $(basename $0)"
    echo "       [-h]                                  : print help"
    echo "       [-v]                                  : verbose output"
    echo "       [-c]                                  : check config and quit"
    echo "       [-l LOCAL_PROXY_PORT ($port_default)] : local socks5 listen port"
    echo "       [-p AWS_PROFILE]                      : aws profile name"
    echo "       [-k AWS_EC2_SSH_KEY_NAME]             : aws ec2 ssh key name"
    echo "       [-f AWS_EC2_SSH_KEY_FILE_NAME]        : aws ec2 ssh key file name"
    echo "       [-s AWS_EC2_SECURITY_GROUP]           : aws ec2 security group"  
    echo "       [-i AWS_EC2_INSTANCE_TYPE]            : aws ec2 instance type"
    echo "       [-a AWS_AMI_ID]                       : aws instance type"
    echo
    echo "       All arguments can be set via environment variables named the"
    echo "       same as shown above in the option arguments. Variables defined"
    echo "       in the environment before runtime will be overridden by shell"
    echo "       variables set in the global config file locate at"
    echo "         $GLOBAL_CONF_FILE,"
    echo "       which in turn will be overridden by shell variables set in"
    echo "       the local config file, $LOCAL_CONF_FILE, which in turn are"
    echo "       overridden by the option arguments."
    echo
}


shutdown_proxy()
{
    echo "Shutting down SSH proxy."
    ssh_cmd="ssh -S ~/.ssh/control/%h_%p_%r \
                 -O exit \
                 ec2-user@$instance_public_ip"
    [ $VERBOSE = yes ] && (echo $ssh_cmd)
    $ssh_cmd > /dev/null 2>&1

    echo "Terminating instance $instance_id."
    aws_cmd="aws $AWS_PROFILE \
                 --output text \
                 --no-cli-pager \
                 ec2 terminate-instances \
                 --instance-ids $instance_id"
    [ $VERBOSE = yes ] && echo $aws_cmd
    $aws_cmd
    if [ $? -ne 0 ]
    then
        echo
        echo "Error terminating instance - log into AWS console and clean up EC2 instances."
        exit 128
    fi
}


# parse command line
args=$(getopt hvcl:p:k:f:s:t:a: $*)
if [ $? -ne 0 ]
then
    usage
    exit 2
fi

set -- $args

while [ $# -ne 0 ]
do
    case "$1" in
        -h)
            usage
            exit 0
            ;;
        -v)
            VERBOSE=yes
            shift;
            ;;
        -c)
            exit_after_config=yes
            VERBOSE=yes
            shift;
            ;;
        -l)
            l_arg="$2"
            shift; shift;
            ;;
        -p)
            p_arg="$2"
            shift; shift;
            ;;
        -k)
            k_arg="$2"
            shift; shift;
            ;;
        -f)
            f_arg="$2"
            shift; shift;
            ;;
        -s)
            s_arg="$2"
            shift; shift;
            ;;
        -t)
            t_arg="$2"
            shift; shift;
            ;;
        -a)
            a_arg="$2"
            shift; shift;
            ;;
        --)
            shift;
            break;
            ;;
    esac
done


# load global configuration file in same directory as script
my_full_name=$(readlink -f ${0} 2>&1)
if [ $? -ne 0 ]
then
    echo "Cannot find script location to load global configuration file.  Skipping."
else
    global_config_file=${my_full_name}.conf
    if [ -f $global_config_file ]
    then
        [ $VERBOSE = yes ] && echo $global_config_file
        . $global_config_file
    fi
fi


# load local configure file in current directory
local_config_file=./$(basename ${0}).conf
if [ -f ${local_config_file} ]
then
    [ $VERBOSE = yes ] && echo $local_config_file
    . $local_config_file
fi


# load config from arguments
[ "$l_arg"X != X ] && LOCAL_PROXY_PORT="$l_arg"
[ "$p_arg"X != X ] && AWS_PROFILE="$p_arg"
[ "$k_arg"X != X ] && AWS_EC2_SSH_KEY_NAME="$k_arg"
[ "$f_arg"X != X ] && AWS_EC2_SSH_KEY_FILE_NAME="$f_arg"
[ "$s_arg"X != X ] && AWS_EC2_SECURITY_GROUP="$s_arg"
[ "$t_arg"X != X ] && AWS_EC2_INSTANCE_TYPE="$t_arg"
[ "$a_arg"X != X ] && AWS_EC2_AMI_ID="$a_arg"


# check config

# use proxy port if not set
if [ "$LOCAL_PROXY_PORT"X = X ]
then
    LOCAL_PROXY_PORT=$port_default
fi

# security group and profile will be default if not set
if [ "$AWS_PROFILE"X = X ]
then
    echo "AWS_PROFILE not set - default profile will be used by aws cli."
else
    AWS_PROFILE="--profile $AWS_PROFILE"
fi

if [ "$AWS_EC2_SECURITY_GROUP"X = X ]
then
    echo "AWS_EC2_SECURITY_GROUP not set - default group be used by AWS EC2."
else
    AWS_EC2_SECURITY_GROUP="--security-group-ids $AWS_EC2_SECURITY_GROUP"
fi


if [ "$VERBOSE"X = "yesX" ]
then
    echo
    echo "VERBOSE:                   $VERBOSE"
    echo "LOCAL_PROXY_PORT:          $LOCAL_PROXY_PORT"
    echo "AWS_PROFILE:               $AWS_PROFILE"
    echo "AWS_EC2_SSH_KEY_NAME:      $AWS_EC2_SSH_KEY_NAME"
    echo "AWS_EC2_SSH_KEY_FILE_NAME: $AWS_EC2_SSH_KEY_FILE_NAME"
    echo "AWS_EC2_SECURITY_GROUP:    $AWS_EC2_SECURITY_GROUP"
    echo "AWS_EC2_INSTANCE_TYPE:     $AWS_EC2_INSTANCE_TYPE"
    echo "AWS_EC2_AMI_ID:            $AWS_EC2_AMI_ID"
    echo
fi


# following variables must be set
conf_error=no
[ "$LOCAL_PROXY_PORT"X = X ]          && echo "LOCAL_PROXY_PORT not set"          && conf_error=yes
[ "$AWS_EC2_SSH_KEY_NAME"X = X ]      && echo "AWS_EC2_SSH_KEY_NAME not set"      && conf_error=yes
[ "$AWS_EC2_SSH_KEY_FILE_NAME"X = X ] && echo "AWS_EC2_SSH_KEY_FILE_NAME not set" && conf_error=yes
[ "$AWS_EC2_INSTANCE_TYPE"X = X ]     && echo "AWS_EC2_INSTANCE_TYPE not set"     && conf_error=yes
[ "$AWS_EC2_AMI_ID"X = X ]            && echo "AWS_EC2_AMI_ID not set"            && conf_error=yes


# check for .ssh/control
if [ ! -d ~/.ssh/control ]
then
    echo "This scripts requires ~/.ssh/control to exist"
    echo "with perms set to 0700."
    echo "$ mkdir ~/.ssh/control"
    echo "$ chmod 0700 ~/.ssh/control"
    conf_error=yes
else
    if [ $(ls -ld ~/.ssh/control | cut -c 2-10) != "rwx------" ]
    then
        echo "This script requires permisions on ~/.ssh/control"
        echo "to be 0700."
        echo "$ chmod 0700 ~/.ssh/control"
        conf_error=yes
    fi
fi

if [ $conf_error != no ]
then
    echo "Configuration error -- exiting."
    exit 3
fi

[ "$exit_after_config"X = yesX ] && exit 0


# get the AMI ID for the latest Amazon Linux AMI
#   I got this code from a google search, I don't really
#   know what the aws ssm service does

#echo "Getting AMI ID for latest Amazon Linux AMI:  \c"
#AWS_EC2_AMI_ID="X"
#AWS_EC2_AMI_ID=$(aws $AWS_PROFILE \
#             --output text \
#             ssm get-parameters \
#             --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
#             --query 'Parameters[0].[Value]')
#
#if [ $AWS_EC2_AMI_ID != "X" ]
#then
#    echo $AWS_EC2_AMI_ID
#else
#    echo
#    echo "Error getting latest Amazon Linux AMI ID."
#    exit 1
#fi


# setup a trap that will terminate the instance before we start it
#    hangup, interrupt, quit and kill 
trap "echo; shutdown_proxy; exit 255" 1 2 3 15


# launch the instance and capture the instance id

echo "Launching instance:  \c"
[ $VERBOSE = yes ] && echo
aws_cmd="aws $AWS_PROFILE \
             --no-cli-pager \
             --output yaml \
             ec2 run-instances \
             --count 1 \
             --instance-type $AWS_EC2_INSTANCE_TYPE \
             --key-name $AWS_EC2_SSH_KEY_NAME \
             $AWS_EC2_SECURITY_GROUP \
             --image-id $AWS_EC2_AMI_ID"
[ $VERBOSE = yes ] && echo $aws_cmd
cmd_output=$($aws_cmd)
if [ $? -eq 0 ]
then
    instance_id=$(echo "$cmd_output" | grep InstanceId | cut -d ":" -f 2 | sed 's/ //')
    echo "success - $instance_id"
else
    echo
    echo "Error launching instance."
    exit 4
fi


# wait for the instance to enter running state

echo "Waiting for instance to enter running state:  \c"
instance_state=stopped
wait_count=0
while [ "$instance_state" != "running" ]
do
    wait_count=$((wait_count + 1))
    if [ $wait_count -gt 10 ]
    then
        echo
        echo "Timeout."
        shutdown_proxy
        exit 5
    fi

    aws_cmd="aws $AWS_PROFILE \
                 --output yaml \
                 --no-cli-pager \
                 ec2 describe-instances \
                 --instance-ids $instance_id"
    [ $VERBOSE = yes ] && (echo; echo $aws_cmd)
    cmd_output=$($aws_cmd)
    if [ $? -ne 0 ]
    then
        echo "Failed to get state."
        shutdown_proxy
        exit 6
    fi
    instance_state=$(echo "$cmd_output" | grep -A 2 State | grep Name | cut -d ":" -f 2 | sed 's/ //')
    [ $VERBOSE = yes ] && echo $instance_state

    # 5 second wait loop with dots after the call,
    # which will give sshd some to start
    instance_indicator=$(echo $instance_state | cut -c 1)
    loop_count=0
    while [ $loop_count -lt 5 ]
    do
        loop_count=$((loop_count + 1))
        sleep 1
        echo "$instance_indicator\c"
    done
done
echo


# get the public IP address of the instance

echo "Getting the public IP address:  \c"
aws_cmd="aws $AWS_PROFILE \
             --no-cli-pager \
             --output yaml \
             ec2 describe-instances \
             --instance-ids $instance_id"
[ $VERBOSE = yes ] && (echo; echo $aws_cmd)
cmd_output=$($aws_cmd)
if [ $? -eq 0 ]
then
    instance_public_ip=$(echo "$cmd_output" | grep PublicIpAddress | cut -d ":" -f 2 | sed 's/ //')
    echo "success - $instance_public_ip"
else
    echo
    echo "Error getting public ip."
    shutdown_proxy
    exit 7
fi


# make the SSH proxy connection in the backgound so we can ask
#  it to exit when done

echo "Making ssh socks5 connection to $instance_public_ip:  \c"

ssh_cmd="ssh -i ~/.ssh/$AWS_EC2_SSH_KEY_FILE_NAME \
             -f -n -N -M \
             -S ~/.ssh/control/%h_%p_%r \
             -D $LOCAL_PROXY_PORT \
             -o StrictHostKeyChecking=no \
             -o UserKnownHostsFile=/dev/null \
             ec2-user@$instance_public_ip"
wait_count=0
[ $VERBOSE = yes ] && (echo; echo $ssh_cmd)
ssh_running=yes
$ssh_cmd > /dev/null 2>&1
while [ $? -ne 0 ]
do
    wait_count=$((wait_count + 1))
    if [ $wait_count -gt 10 ]
    then
        echo
        echo "Giving up."
        shutdown_proxy
        exit 8
        break
    fi
    
    loop_count=0
    while [ $loop_count -lt 5 ]
    do
        loop_count=$((loop_count + 1))
        sleep 1
        echo ".\c"
    done
    [ $VERBOSE = yes ] && (echo; echo $ssh_cmd)
    $ssh_cmd > /dev/null 2>&1
done

echo "success - port $LOCAL_PROXY_PORT"
ssh_exit=no
while [ $ssh_exit = "no" ]
do
    echo "Type exit <enter> to quit >  \c"
    read read_response
    if [ "$read_response"X = "exitX" ]
    then
        ssh_exit=yes
    fi
done


# terminate the instance
shutdown_proxy

exit 0
