#!/bin/bash

AMI=ami-0b4f379183e5706b9   # ✅ Replace with dynamic AMI fetch if needed
SG_ID=sgr-030b47b7bc3472b99 # ✅ Your Security Group ID
INSTANCES=("mongodb" "redis" "mysql" "rabbitmq" "catalogue" "user" "cart" "shipping" "payment" "dispatch" "web")
ZONE_ID=Z055763434TXUZ9JMBMT3 # ✅ Your hosted zone ID
DOMAIN_NAME="jhansidevops.icu"

for i in "${INSTANCES[@]}"
do
    if [ "$i" == "mongodb" ] || [ "$i" == "mysql" ] || [ "$i" == "shipping" ]; then
        INSTANCE_TYPE="t3.small"
    else
        INSTANCE_TYPE="t2.micro"
    fi

    # STEP 1: Launch instance and capture Instance ID
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id $AMI \
        --instance-type $INSTANCE_TYPE \
        --security-group-ids $SG_ID \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$i}]" \
        --query 'Instances[0].InstanceId' \
        --output text)

    # STEP 2: Wait until instance is running
    aws ec2 wait instance-running --instance-ids $INSTANCE_ID

    # STEP 3: Fetch IP (choose Private OR Public)
    IP_ADDRESS=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].PrivateIpAddress' \
        --output text)

    # 👉 If you need external DNS, change above line to:
    # --query 'Reservations[0].Instances[0].PublicIpAddress'

    echo "$i: $IP_ADDRESS"

    # STEP 4: Skip Route53 if IP is empty
    if [ -z "$IP_ADDRESS" ]; then
        echo "No IP found for $i, skipping DNS record"
        continue
    fi

    # STEP 5: UPSERT record with TTL = 1
    aws route53 change-resource-record-sets \
    --hosted-zone-id $ZONE_ID \
    --change-batch "{
        \"Comment\": \"Creating record set for $i\",
        \"Changes\": [{
            \"Action\": \"UPSERT\",
            \"ResourceRecordSet\": {
                \"Name\": \"$i.$DOMAIN_NAME\",
                \"Type\": \"A\",
                \"TTL\": 1,
                \"ResourceRecords\": [{\"Value\": \"$IP_ADDRESS\"}]
            }
        }]
    }"
done