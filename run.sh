#!/bin/bash

set -euxo pipefail

# Simple Helm Lab Test Script
# Tests the essential steps from the Helm lab

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

cleanup() {
    log_info "Cleaning up..."
    helm uninstall my-nginx 2>/dev/null || true
    cd ..
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

# Main test
log_info "Starting Simple Helm Test"

# Check prerequisites
if ! command -v helm &> /dev/null || ! command -v kubectl &> /dev/null; then
    log_error "helm or kubectl not found"
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    log_error "No Kubernetes cluster available"
    exit 1
fi

log_success "Prerequisites OK"

# Create test directory
TEST_DIR="helm-test-$(date +%s)"
mkdir "$TEST_DIR" && cd "$TEST_DIR"

# Step 1: Create chart
log_info "Step 1: Creating Helm chart"
helm create demo-app
log_success "Chart created"

# Step 2: Configure values
log_info "Step 2: Configuring values"
cat > demo-app/values.yaml << 'EOF'
replicaCount: 1

image:
  repository: nginxinc/nginx-unprivileged
  pullPolicy: IfNotPresent
  tag: "1.28.0-alpine3.21-perl"

nameOverride: ""
fullnameOverride: ""

serviceAccount:
  create: true
  automount: true
  annotations: {}
  name: ""

podAnnotations: {}
podLabels: {}

podSecurityContext: {}
securityContext: {}

service:
  type: ClusterIP
  port: 8080

ingress:
  enabled: false

resources:
  limits:
    cpu: 100m
    memory: 128Mi
  requests:
    cpu: 50m
    memory: 64Mi

livenessProbe:
  httpGet:
    path: /
    port: 8080 
readinessProbe:
  httpGet:
    path: /
    port: 8080

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 100
  targetCPUUtilizationPercentage: 80

volumes: []
volumeMounts: []
nodeSelector: {}
tolerations: []
affinity: {}
EOF

log_success "Values configured"

# Step 3: Deploy
log_info "Step 3: Deploying application"
helm install my-nginx ./demo-app

# Wait a bit for deployment
sleep 10
kubectl wait --for=condition=available deployment/my-nginx-demo-app --timeout=60s

log_success "Application deployed"

# Step 4: Test scaling
log_info "Step 4: Testing scaling"
helm upgrade my-nginx ./demo-app --set replicaCount=2
sleep 5
kubectl wait --for=condition=available deployment/my-nginx-demo-app --timeout=60s

# Check replicas
REPLICAS=$(kubectl get deployment my-nginx-demo-app -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
if [[ "$REPLICAS" == "2" ]]; then
    log_success "Scaling to 2 replicas successful"
else
    log_error "Scaling failed - expected 2, got '$REPLICAS'"
fi

# Step 5: Test application
log_info "Step 5: Testing application"
kubectl port-forward service/my-nginx-demo-app 8080:8080 &
PF_PID=$!
sleep 3

if curl -s http://localhost:8080 | grep -q "nginx"; then
    log_success "Application responds correctly"
else
    log_error "Application not responding"
fi

kill $PF_PID 2>/dev/null || true

# Step 6: Cleanup
cleanup

log_info "Simple Helm test completed successfully!"
