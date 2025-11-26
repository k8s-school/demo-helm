#!/bin/bash

# Helm Chart TP - Automated Demo Script (Non-Interactive)
# This script demonstrates the complete Helm chart workflow

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_step() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_command() {
    echo -e "${CYAN}$ $1${NC}"
}

# Function to execute and display commands
execute_command() {
    local cmd="$1"
    local description="$2"

    if [ -n "$description" ]; then
        echo -e "${YELLOW}$description${NC}"
    fi

    print_command "$cmd"
    eval "$cmd"
    echo ""
}

# Function to check if kubectl is working
check_prerequisites() {
    print_step "Checking Prerequisites"

    if ! command -v helm &> /dev/null; then
        print_error "Helm is not installed. Please install helm first."
        exit 1
    fi

    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        print_error "kubectl cannot connect to cluster. Please check your kubeconfig."
        exit 1
    fi

    print_success "All prerequisites are met"
    print_success "Helm version: $(helm version --short)"
    print_success "Kubectl context: $(kubectl config current-context)"
    echo ""
}

# Function to clean up previous installations
cleanup() {
    print_step "Cleaning Up Previous Installations"

    echo "Removing any existing releases..."
    execute_command "helm uninstall my-demo-app || echo 'Release my-demo-app not found'" "Uninstalling my-demo-app if it exists"
    execute_command "helm uninstall my-demo-app-prod || echo 'Release my-demo-app-prod not found'" "Uninstalling my-demo-app-prod if it exists"

    echo "Waiting for cleanup to complete..."
    sleep 3

    print_success "Cleanup completed"
}

# Function to create and configure the chart
create_chart() {
    print_step "Creating and Configuring Helm Chart"

    # Remove existing chart if it exists
    if [ -d "demo-app" ]; then
        execute_command "rm -rf demo-app" "Removing existing demo-app directory"
    fi

    execute_command "helm create demo-app" "Creating new Helm chart"

    print_success "Base chart created successfully!"
}

# Function to configure the chart
configure_chart() {
    print_step "Configuring Chart for nginx-unprivileged"

    # Update values.yaml for nginx unprivileged
    execute_command "sed -i 's|repository: nginx|repository: nginxinc/nginx-unprivileged|g' demo-app/values.yaml" "Updating image repository"
    execute_command "sed -i 's|tag: \"\"|tag: \"1.28.0-alpine3.21-perl\"|g' demo-app/values.yaml" "Setting image tag"

    # Add configmap configuration to values.yaml
    cat >> demo-app/values.yaml << 'EOF'

# ConfigMap configuration for nginx
configmap:
  enabled: true
  data:
    index.html: |
      <!DOCTYPE html>
      <html>
      <head>
          <title>Welcome to Demo App</title>
      </head>
      <body>
          <h1>Hello from Helm Chart Demo!</h1>
          <p>This is a demo nginx application deployed with Helm.</p>
      </body>
      </html>
EOF

    print_success "Updated values.yaml with nginx unprivileged image and ConfigMap"

    # Create ConfigMap template
    cat > demo-app/templates/configmap.yaml << 'EOF'
{{- if .Values.configmap.enabled }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "demo-app.fullname" . }}-config
  labels:
    {{- include "demo-app.labels" . | nindent 4 }}
data:
  {{- range $key, $value := .Values.configmap.data }}
  {{ $key }}: |
{{ $value | indent 4 }}
  {{- end }}
{{- end }}
EOF

    print_success "Created ConfigMap template"

    # Update deployment template for container port
    execute_command "sed -i 's|containerPort: {{ .Values.service.port }}|containerPort: 8080|g' demo-app/templates/deployment.yaml" "Fixing container port to 8080"

    # Add volume mount for ConfigMap to deployment
    # This requires a more complex sed operation, so we'll use a temporary file
    python3 << 'EOF'
import re

# Read the deployment file
with open('demo-app/templates/deployment.yaml', 'r') as f:
    content = f.read()

# Add volume mount after resources section
volume_mount = '''          volumeMounts:
            {{- if .Values.configmap.enabled }}
            - name: nginx-config
              mountPath: /usr/share/nginx/html
              readOnly: true
            {{- end }}
            {{- with .Values.volumeMounts }}
            {{- toYaml . | nindent 12 }}
            {{- end }}'''

# Replace existing volumeMounts section
if 'volumeMounts:' in content:
    content = re.sub(
        r'          \{\{- with \.Values\.volumeMounts \}\}\n          volumeMounts:\n            \{\{- toYaml \. \| nindent 12 \}\}\n          \{\{- end \}\}',
        volume_mount,
        content
    )
else:
    # Add after resources section
    content = re.sub(
        r'(          resources:\n            \{\{- toYaml \.Values\.resources \| nindent 12 \}\})',
        r'\1\n' + volume_mount,
        content
    )

# Add volumes section
volume_section = '''      volumes:
        {{- if .Values.configmap.enabled }}
        - name: nginx-config
          configMap:
            name: {{ include "demo-app.fullname" . }}-config
        {{- end }}
        {{- with .Values.volumes }}
        {{- toYaml . | nindent 8 }}
        {{- end }}'''

# Replace existing volumes section
content = re.sub(
    r'      \{\{- with \.Values\.volumes \}\}\n      volumes:\n        \{\{- toYaml \. \| nindent 8 \}\}\n      \{\{- end \}\}',
    volume_section,
    content
)

# Write back the file
with open('demo-app/templates/deployment.yaml', 'w') as f:
    f.write(content)

print("Updated deployment template with ConfigMap volume mount")
EOF

    print_success "Updated deployment template with ConfigMap volume mount and volume"

    print_success "Chart configuration completed!"
}

# Function to demonstrate chart structure
show_chart_structure() {
    print_step "Chart Structure Overview"

    echo "The demo-app chart structure:"
    execute_command "find demo-app -type f | head -15" "Listing chart files"

    echo ""
    echo "Key modifications made:"
    echo "• Image: nginxinc/nginx-unprivileged:1.28.0-alpine3.21-perl"
    echo "• Container port: 8080 (nginx unprivileged default)"
    echo "• Added ConfigMap for custom HTML content"
    echo "• Volume mount for /usr/share/nginx/html"
    echo ""
}

# Function to validate chart
validate_chart() {
    print_step "Chart Validation"

    execute_command "helm lint ./demo-app" "Linting the chart"
    execute_command "helm template test-release ./demo-app | head -20" "Testing chart templating (first 20 lines)"
}

# Function to demonstrate basic deployment
demo_basic_deployment() {
    print_step "Basic Deployment with Default Values"

    execute_command "helm install my-demo-app ./demo-app" "Installing chart with default values"

    print_success "Chart installed successfully!"

    echo "Waiting for deployment to be ready..."
    execute_command "kubectl rollout status deployment/my-demo-app --timeout=120s" "Checking deployment rollout status"

    execute_command "kubectl get pods,svc,configmap -l app.kubernetes.io/name=demo-app" "Viewing created resources"
}

# Function to test the application
test_application() {
    print_step "Testing the Application"

    execute_command "kubectl get svc my-demo-app" "Checking service details"

    echo "Testing application connectivity..."
    execute_command "kubectl run test-pod --rm -i --restart=Never --image=curlimages/curl -- curl -s http://my-demo-app/index.html | head -5" "Testing internal connectivity"

    print_success "Application is responding correctly!"
}

# Function to demonstrate --set usage
demo_set_flags() {
    print_step "Customization with --set Flags"

    execute_command "helm upgrade my-demo-app ./demo-app --set replicaCount=3" "Scaling replicas to 3"

    execute_command "kubectl get pods -l app.kubernetes.io/name=demo-app" "Checking scaled pods"

    execute_command "helm upgrade my-demo-app ./demo-app --set replicaCount=3 --set 'configmap.data.index\.html=<h1>Updated via --set</h1><p>Content changed using --set flag!</p>'" "Updating content via --set"

    print_success "Content updated successfully!"

    execute_command "helm get values my-demo-app" "Viewing current values"
}

# Function to demonstrate values files
demo_values_files() {
    print_step "Customization with Values Files"

    echo "Development environment values (values-dev.yaml):"
    execute_command "head -10 values-dev.yaml" "Showing dev values file"

    execute_command "helm upgrade my-demo-app ./demo-app -f values-dev.yaml" "Deploying with dev values"

    execute_command "kubectl rollout status deployment/my-demo-app" "Waiting for dev deployment"

    execute_command "kubectl get pods,svc -l app.kubernetes.io/name=demo-app" "Checking dev deployment"

    echo "Production environment values (values-prod.yaml):"
    execute_command "head -10 values-prod.yaml" "Showing prod values file"

    execute_command "helm install my-demo-app-prod ./demo-app -f values-prod.yaml" "Installing prod environment"

    execute_command "kubectl rollout status deployment/my-demo-app-prod" "Waiting for prod deployment"

    echo "Waiting for production deployment to be fully ready..."
    execute_command "kubectl wait --for=condition=available --timeout=300s deployment/my-demo-app-prod" "Ensuring prod deployment is available"

    execute_command "kubectl get pods,svc -l app.kubernetes.io/instance=my-demo-app-prod" "Checking prod deployment"
}

# Function to demonstrate validation
demo_validation() {
    print_step "Validation and Inspection"

    execute_command "helm list" "Listing all releases"

    execute_command "kubectl get deployments" "All deployments"

    execute_command "kubectl get pods -l app.kubernetes.io/name=demo-app" "All demo-app pods"

    execute_command "kubectl get configmap -l app.kubernetes.io/name=demo-app -o name" "ConfigMaps"

    execute_command "kubectl describe deployment my-demo-app | grep -A5 'Image:'" "Checking image configuration"

    print_success "All resources are deployed correctly!"
}

# Function to demonstrate advanced operations
demo_advanced_operations() {
    print_step "Advanced Helm Operations"

    execute_command "helm history my-demo-app" "Viewing release history"

    execute_command "helm get manifest my-demo-app | head -20" "Viewing generated manifests (first 20 lines)"

    echo "Demonstrating dry-run:"
    execute_command "helm upgrade my-demo-app ./demo-app --set replicaCount=5 --dry-run" "Dry-run upgrade"

    echo "Rolling back to previous version:"
    execute_command "helm rollback my-demo-app" "Rolling back"

    execute_command "helm history my-demo-app" "Updated history after rollback"
}

# Function to test different environments
test_environments() {
    print_step "Testing Different Environments"

    echo "Testing development environment:"
    execute_command "kubectl run test-dev --rm -i --restart=Never --image=curlimages/curl -- curl -s http://my-demo-app:8080/index.html | grep -E '<title>|<h1>'" "Testing dev environment content"

    echo "Testing production environment:"
    execute_command "kubectl get svc my-demo-app-prod" "Verifying production service exists"
    execute_command "kubectl run test-prod --rm -i --restart=Never --image=curlimages/curl -- curl -s --max-time 30 http://my-demo-app-prod/index.html | grep -E '<title>|<h1>'" "Testing prod environment content"

    print_success "Both environments are responding correctly!"
}

# Function to show useful commands
show_useful_commands() {
    print_step "Useful Helm Commands Reference"

    echo "Chart management:"
    echo "  helm create <chart-name>           # Create new chart"
    echo "  helm lint <chart>                  # Validate chart"
    echo "  helm template <release> <chart>    # Generate manifests"
    echo ""

    echo "Installation and upgrades:"
    echo "  helm install <release> <chart>     # Install chart"
    echo "  helm upgrade <release> <chart>     # Upgrade release"
    echo "  helm uninstall <release>           # Remove release"
    echo ""

    echo "Customization:"
    echo "  --set key=value                    # Override single value"
    echo "  -f values.yaml                     # Use values file"
    echo "  --dry-run                          # Test without applying"
    echo ""

    echo "Information:"
    echo "  helm list                          # List releases"
    echo "  helm status <release>              # Release status"
    echo "  helm get values <release>          # Current values"
    echo "  helm history <release>             # Release history"
    echo ""
}

# Function to final cleanup
final_cleanup() {
    print_step "Cleanup Options"

    if [ "$1" = "--cleanup" ]; then
        echo "Cleaning up all resources..."
        execute_command "helm uninstall my-demo-app" "Uninstalling dev release"
        execute_command "helm uninstall my-demo-app-prod" "Uninstalling prod release"

        echo "Waiting for cleanup to complete..."
        sleep 5

        execute_command "kubectl get all -l app.kubernetes.io/name=demo-app || echo 'No resources found'" "Checking remaining resources"

        print_success "Cleanup completed!"
    else
        print_warning "Resources remain deployed. To cleanup, run:"
        echo "  helm uninstall my-demo-app"
        echo "  helm uninstall my-demo-app-prod"
        echo "Or run this script with --cleanup flag: ./run.sh --cleanup"
    fi
}

# Function to demonstrate port forwarding
demo_port_forwarding() {
    print_step "Port Forwarding Example"

    echo "To access the applications locally, you can use port forwarding:"
    echo ""
    echo "For development environment:"
    echo "  kubectl port-forward service/my-demo-app 8080:8080"
    echo "  curl http://localhost:8080"
    echo ""
    echo "For production environment:"
    echo "  kubectl port-forward service/my-demo-app-prod 8081:80"
    echo "  curl http://localhost:8081"
    echo ""
}

# Main execution
main() {
    echo -e "${GREEN}"
    echo "=========================================================="
    echo "  Helm Chart TP - Automated Demo Script (Non-Interactive)"
    echo "=========================================================="
    echo -e "${NC}"
    echo ""
    echo "This script demonstrates:"
    echo "• Basic Helm chart deployment"
    echo "• Customization with --set flags"
    echo "• Environment-specific deployments with values files"
    echo "• Advanced Helm operations"
    echo "• Testing and validation"
    echo ""
    echo "Usage: $0 [--cleanup]"
    echo "  --cleanup: Clean up resources at the end"
    echo ""

    check_prerequisites
    cleanup
    create_chart
    configure_chart
    show_chart_structure
    validate_chart
    demo_basic_deployment
    test_application
    demo_set_flags
    demo_values_files
    demo_validation
    test_environments
    demo_advanced_operations
    demo_port_forwarding
    show_useful_commands
    final_cleanup "$1"

    print_step "TP Completed Successfully!"
    print_success "Helm Chart demonstration completed!"
    print_success "Check TP-HELM.md for detailed explanations and manual exercises."

    if [ "$1" != "--cleanup" ]; then
        echo ""
        print_warning "Resources are still running. Use 'kubectl get all' to see them."
        print_warning "Run './run.sh --cleanup' to remove all resources."
    fi
}

# Run the main function
main "$@"