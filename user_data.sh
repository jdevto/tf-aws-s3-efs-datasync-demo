#!/bin/bash

# Update system
yum update -y

# Install EFS utilities and SSM agent
yum install -y amazon-efs-utils amazon-ssm-agent

# Start and enable SSM agent
systemctl start amazon-ssm-agent
systemctl enable amazon-ssm-agent

# Create mount point
mkdir -p /mnt/efs

# Mount EFS file system
mount -t efs -o tls ${efs_id}:/ /mnt/efs

# Create datasync directory for DataSync replication
mkdir -p /mnt/efs/datasync

# Create a test file to verify mount
echo "EFS mount test - $(date)" > /mnt/efs/mount-test.txt

# Add to fstab for persistent mount
echo "${efs_id}:/ /mnt/efs efs defaults,_netdev" >> /etc/fstab

# Create a script to check DataSync files
cat > /home/ec2-user/check-datasync.sh << 'EOF'
#!/bin/bash
echo "=== EFS Mount Status ==="
df -h /mnt/efs

echo -e "\n=== EFS Contents ==="
ls -la /mnt/efs/

echo -e "\n=== DataSync Files (Root Directory) ==="
echo "DataSync files in EFS root:"
ls -la /mnt/efs/ | grep -v "^d" | head -10

echo -e "\n=== Test File Creation ==="
echo "Test file created at $(date)" > /mnt/efs/test-$(date +%s).txt
echo "Test file created successfully"
EOF

chmod +x /home/ec2-user/check-datasync.sh
chown ec2-user:ec2-user /home/ec2-user/check-datasync.sh

# Log completion
echo "EFS mount setup completed at $(date)" >> /var/log/efs-mount.log
