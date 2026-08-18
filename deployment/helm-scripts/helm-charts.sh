#!/bin/bash

set -euo pipefail

# Detect the absolute path of the current script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
LOG_FILE="$SCRIPT_DIR/logs/codemie_helm_deployment_$(date +%Y-%m-%d-%H%M%S).log"
CODEMIE_NAMESPACE="codemie"
AWS_ECR_MARKETPLACE="709825985650.dkr.ecr.us-east-1.amazonaws.com/epam-systems"

if [ ! -d "$SCRIPT_DIR/logs" ]; then
    mkdir "$SCRIPT_DIR/logs"
fi

###################
# Helper Functions
###################

log_message() {
    local status="$1"
    local message="$2"
    # shellcheck disable=SC2155
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$status" in
        "success")
            echo -e "[$timestamp] [OK] $message" ;;
        "fail")
            echo -e "[$timestamp] [ERROR] $message" ;;
        "info")
            echo -e "[$timestamp] $message" ;;
        "warn")
            echo -e "[$timestamp] [WARN] $message" ;;
        *)
            echo -e "[$timestamp] $message" ;;
    esac
}

display_usage() {
    echo "Usage: $0 [options]"
    echo "OPTIONS:"
    echo "  -h, --help                 Display this help message and exit"
    echo "  -v, --version              AI/Run CodeMie version to deploy (e.g. 2.41.0)"
    echo "  -r, --registry             AWS ECR repository from where install Helm charts and deploy images. Optional"
    echo "Examples:"
    echo "$0 --version 2.41.0"
    exit 1
}

check_nsc() {
    if ! hash nsc; then
        log_message "fail" "nsc is not installed"
        log_message "info" "Install nsc by running the following commands:"
        log_message "info" ""
        log_message "info" "curl -sf https://binaries.nats.dev/nats-io/nsc/v2@latest | sh; sudo cp nsc /usr/bin/"
        log_message "info" ""
        exit 1
    fi
}

check_htpasswd() {
    if ! hash htpasswd; then
        log_message "fail" "htpasswd is not installed"
        log_message "info" "Install htpasswd by running the following commands:"
        log_message "info" ""
        log_message "info" "sudo apt-get install apache2-utils"
        log_message "info" ""
        exit 1
    fi
}

check_helm(){
    if ! hash helm &> /dev/null; then
        log_message "fail" "Helm is not installed. Please install Helm to proceed."
        exit 1
    fi
}

verify_inputs() {
    ai_run_version=""
    image_repository=""

    # Parse arguments
    while [[ $# -gt 0 ]]
    do
        case $1 in
            --version|-v)
                ai_run_version="$2"
                shift 2
                ;;
            --registry|-r)
                image_repository="$2"
                shift 2
                ;;
            --help|-h)
                display_usage
                ;;
            *)
                log_message "fail" "Unknown option: $1"
                display_usage
                ;;
        esac
    done

    if [[ -z "$ai_run_version" ]]; then
        log_message "fail" "version is not set."
        display_usage
    fi

    if [[ -n "$image_repository" ]]; then
      log_message "info" "Using custom ECR: $image_repository"
    else
      log_message "info" "Using marketplace ECR: $AWS_ECR_MARKETPLACE"
      image_repository=$AWS_ECR_MARKETPLACE
    fi
}

verify_aws_login() {
    log_message "info" ""
    log_message "info" "Checking AWS login status..."

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_message "fail" "You are not logged into AWS."
        log_message "info" "Please configure AWS credentials using: aws configure"
        exit 1
    fi

    # Get current account details
    local current_account
    current_account=$(aws sts get-caller-identity --query "Account" --output text)
    current_user=$(aws sts get-caller-identity --query "Arn" --output text)

    log_message "info" "Current AWS account:"
    log_message "info" "Account ID: $current_account"
    log_message "info" "User ARN: $current_user"
    log_message "info" ""
}

helm_registry_login() {
  local ecr_region=""
  ecr_region=$(echo "$image_repository" | sed 's/.*\.ecr\.\([^.]*\)\.amazonaws\.com.*/\1/')

  aws ecr get-login-password --region $ecr_region | helm registry login --username AWS --password-stdin "${image_repository%/*}"
}

check_and_create_namespace() {
    local namespace=$1

    # Check if the namespace exists
    if kubectl get namespace "$namespace" > /dev/null 2>&1; then
        log_message "info" "Namespace '$namespace' already exists."
    else
        # Create the namespace
        log_message "info" "Namespace '$namespace' does not exist. Creating..."

        if kubectl create namespace "$namespace" > /dev/null 2>&1; then
            log_message "success" "Namespace '$namespace' created successfully."
        else
            log_message "fail" "Failed to create namespace '$namespace'."
            exit 1
        fi
    fi
}

check_k8s_secret_exists() {
    local namespace="$1"
    local secret_name="$2"

    if kubectl get secret "$secret_name" -n "$namespace" > /dev/null 2>&1; then
        log_message "info" "Secret '$secret_name' exists in namespace '$namespace'."
        return 0
    else
        log_message "info" "Secret '$secret_name' does not exist in namespace '$namespace'."
        return 1
    fi
}

check_k8s_configmap_exists() {
  local namespace="$1"
  local config_name="$2"

  if kubectl -n "$namespace" get configmap "$config_name" > /dev/null 2>&1; then
    log_message "info" "ConfigMap '$config_name' exists in namespace '$namespace'."
    return 0
  else
    log_message "info" "ConfigMap '$config_name' does not exist in namespace '$namespace'."
    return 1
  fi
}

check_env_vars() {
    local missing_vars=0

    for var in "$@"; do
        if [ -z "${!var:-}" ]; then
            log_message "warn" "Environment variable $var is not set."
            missing_vars=1
        fi
    done

    return $missing_vars
}

load_deployment_env() {
  SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
  TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")/terraform-scripts"
  OUTPUT_FILE="$TERRAFORM_DIR/deployment_outputs.env"

  if [ -f "$OUTPUT_FILE" ]; then
      log_message "info" "Loading outputs from $OUTPUT_FILE"
      set -a
      source "$OUTPUT_FILE"
      set +a
  else
      log_message "fail" "Can not locate 'deployment_outputs.env' file"
      exit 1
  fi
}

configure_kubectl() {
    log_message "info" "Configuring kubectl with current cluster ..."
    aws eks update-kubeconfig --region ${CODEMIE_PLATFORM_REGION} --name ${CODEMIE_PLATFORM_NAME}
}

print_summary() {
    log_message "info" "Deployment Summary"
    log_message "info" "=================="
    log_message "info" "CodeMie URL: https://codemie.${CODEMIE_DOMAIN_NAME}/"
    log_message "info" "SuperUser: $(kubectl -n codemie get secret codemie-access -o jsonpath="{.data.email}" | base64 --decode)"
    log_message "info" "Password: $(kubectl -n codemie get secret codemie-access -o jsonpath="{.data.password}" | base64 --decode)"
    log_message "info" "=================="
    log_message "info" "All deployments completed successfully."
    log_message "info" "Deployment outputs have been saved to deployment_outputs.env"
    log_message "info" "Log file: $LOG_FILE"
}

###################
# Deployment Steps
###################
deploy_storage_class() {
  log_message "info" "Deploying Storage Class ..."
  kubectl apply -f "storage-class/storageclass-aws-gp3.yaml" > /dev/null
}

deploy_nginx_ingress_controller() {
    local namespace="ingress-nginx"

    log_message "info" "Starting Nginx Ingress Controller deployment"

    check_and_create_namespace "$namespace"

    log_message "info" "Deploying Nginx Ingress Controller Helm Chart ..."
    helm upgrade \
      --install ingress-nginx ingress-nginx/. \
      --namespace "$namespace" \
      --values "ingress-nginx/values.yaml" \
      --wait \
      --timeout 900s \
      --dependency-update > /dev/null

    # shellcheck disable=SC2181
    if [ $? -eq 0 ]; then
        log_message "success" "Nginx Ingress Controller deployment completed"
    else
        log_message "fail" "Failed to deploy Nginx Ingress Controller."
        exit 1
    fi

    log_message "success" "Nginx Ingress Controller configuration completed"
}

deploy_elasticsearch() {
  local namespace="elastic"
  local secret_name="elasticsearch-master-credentials"

  log_message "info" "Starting Elasticsearch deployment"

  check_and_create_namespace "$namespace"

  if ! check_k8s_secret_exists "$namespace" "$secret_name"; then
      kubectl -n $namespace create secret generic $secret_name \
      --from-literal=username=elastic \
      --from-literal=password="$(openssl rand -base64 12 | tr -d '/+=')" \
      --type=Opaque \
      --dry-run=client -o yaml | kubectl apply -f - > /dev/null
  fi

  log_message "info" "Deploying Elasticsearch Helm Chart ..."
  helm upgrade \
    --install elastic elasticsearch/. \
    --namespace "$namespace" \
    --values "elasticsearch/values.yaml" \
    --wait \
    --timeout 900s \
    --dependency-update > /dev/null

  # shellcheck disable=SC2181
  if [ $? -eq 0 ]; then
    log_message "success" "Elasticsearch deployment completed"
  else
    log_message "fail" "Failed to deploy Elasticsearch."
    exit 1
  fi
}

deploy_kibana() {
    local namespace="elastic"
    local values_file="kibana/values.yaml"
    local domain_value="$1"

    log_message "info" "Starting Kibana deployment"

    if check_k8s_secret_exists "$namespace" "kibana-kibana-es-token"; then
        kubectl delete secret kibana-kibana-es-token -n $namespace > /dev/null 2>&1
        # shellcheck disable=SC2181
        if [ $? -eq 0 ]; then
            log_message "success" "Secret 'kibana-kibana-es-token' removed successfully."
        else
            log_message "fail" "Failed to remove kibana-kibana-es-token secret."
            exit 1
        fi
    fi

    log_message "info" "Deploying Kibana Helm Chart ..."
    helm upgrade \
      --install kibana kibana/. \
      --namespace "$namespace" \
      --values "${values_file}" \
      --set "kibana.ingress.hosts[0].host=kibana.$domain_value" \
      --wait \
      --timeout 900s \
      --dependency-update > /dev/null

    # shellcheck disable=SC2181
    if [ $? -eq 0 ]; then
        log_message "success" "Kibana deployment completed"
        log_message "info" "Kibana is available at: https://kibana.${domain_value}"
    else
        log_message "fail" "Failed to deploy Kibana."
        exit 1
    fi
}

deploy_fluent_bit() {
    local namespace="fluentbit"
    local values_file="./fluent-bit/values.yaml"

    log_message "info" "Starting FluentBit deployment"
    check_and_create_namespace "$namespace"

    if ! check_k8s_secret_exists "$namespace" "elasticsearch-master-credentials"; then
        kubectl get secret elasticsearch-master-credentials -n elastic -o yaml | sed '/namespace:/d' | kubectl apply -n "$namespace" -f - > /dev/null
        # shellcheck disable=SC2181
        if [ $? -eq 0 ]; then
            log_message "success" "Secret 'elasticsearch-master-credentials' created successfully."
        else
            log_message "fail" "Failed to create secret 'elasticsearch-master-credentials'."
            exit 1
        fi
    fi

    if ! check_k8s_configmap_exists "$namespace" "config"; then
      kubectl -n "$namespace" create configmap "config" \
        --from-literal=AWS_REGION="$AWS_DEFAULT_REGION" \
        > /dev/null
    fi

    helm upgrade --install fluent-bit fluent-bit/. \
      --namespace "$namespace" \
      -f "${values_file}" \
      --wait \
      --timeout 180s \
      --dependency-update > /dev/null

    # shellcheck disable=SC2181
    if [ $? -eq 0 ]; then
        log_message "success" "FluentBit deployment completed"
    else
        log_message "fail" "Failed to deploy FluentBit."
        exit 1
    fi
}

deploy_codemie_ui() {
    local namespace="codemie"
    local ai_run_version="$1"
    local image_repository="$2"
    local domain_value="$3"
    local values_file="./codemie-ui/values.yaml"
    local helm_repository="oci://$image_repository/codemie-ui"

    log_message "info" "Starting AI/Run UI deployment"

    check_and_create_namespace "$namespace"

    log_message "info" "Deploying AI/Run UI Helm Chart ..."
    helm upgrade --install codemie-ui "$helm_repository" \
      --version "${ai_run_version}" \
      --namespace "$namespace" \
      -f "${values_file}" \
      --set "image.repository=$image_repository/codemie-ui" \
      --set "image.tag=$ai_run_version-oss" \
      --set "viteApiUrl=https://codemie.$domain_value/code-assistant-api" \
      --set "ingress.host=codemie.$domain_value" \
      --set "viteMcpAuthOrigin=https://codemie.$domain_value/code-assistant-api" \
      --wait \
      --timeout 180s \
      --dependency-update > /dev/null

    # shellcheck disable=SC2181
    if [ $? -eq 0 ]; then
        log_message "success" "AI/Run UI deployment completed"
    else
        log_message "fail" "Failed to deploy AI/Run UI."
        exit 1
    fi
}

configure_elasticsearch_access() {
  local namespace="$1"
  local secrets_list=(
    "elasticsearch-master-credentials"
    "elasticsearch-master-certs"
  )

  check_and_create_namespace "$namespace"

  for secret_name in "${secrets_list[@]}"; do
    echo "Ensure $secret_name present in namespace $namespace"
    kubectl get secret "$secret_name" -n elastic -o yaml | \
     sed '/namespace:/d' | \
     sed '/creationTimestamp:/d' | \
     sed '/resourceVersion:/d' | \
     sed '/uid:/d' | \
     kubectl apply -n "$namespace" -f - > /dev/null
    # shellcheck disable=SC2181
    if [ $? -eq 0 ]; then
      log_message "success" "Secret '$secret_name' created/updated successfully in '$namespace' namespace."
    else
      log_message "fail" "Failed to create/update secret '$secret_name' in '$namespace' namespace."
      exit 1
    fi
  done

  # Patch secret to set CA Certificate Hash
  local ca_subject_hash=$(kubectl -n "$namespace" get secret "elasticsearch-master-certs" -o jsonpath='{.data.ca\.crt}' | base64 -d | openssl x509 -noout -subject_hash)

  kubectl -n "$namespace" patch secret elasticsearch-master-certs -p "{\"stringData\":{\"ca.hash\":\"$ca_subject_hash\"}}"

}

deploy_codemie_api() {
    local namespace="codemie"
    local ai_run_version="$1"
    local image_repository="$2"
    local domain_value="$3"
    local helm_repository="oci://$image_repository/codemie"
    local values_file="./codemie-api/values.yaml"
    local postgres_secret_name="codemie-postgresql"

    log_message "info" "Starting AI/Run API deployment"

    check_and_create_namespace "$namespace"
    configure_elasticsearch_access "$namespace"

    if ! check_k8s_secret_exists "$namespace" "$postgres_secret_name"; then
        kubectl -n $namespace create secret generic $postgres_secret_name \
            --from-literal=password="${AWS_RDS_DATABASE_PASSWORD}" \
            --from-literal=user="${AWS_RDS_DATABASE_USER}" \
            --from-literal=db-url="${AWS_RDS_ADDRESS}" \
            --from-literal=db-name="${AWS_RDS_DATABASE_NAME}" > /dev/null

        # shellcheck disable=SC2181
        if [ $? -eq 0 ]; then
            log_message "success" "Secret '$postgres_secret_name' created successfully."
        else
            log_message "fail" "Failed to create secret '$postgres_secret_name'."
            exit 1
        fi
    fi

    if ! check_k8s_configmap_exists "$namespace" "codemie-config"; then
      kubectl -n "$namespace" create configmap "codemie-config" \
        --from-literal=AWS_DEFAULT_REGION="$AWS_DEFAULT_REGION" \
        --from-literal=AWS_KMS_KEY_ID="$AWS_KMS_KEY_ID" \
        --from-literal=AWS_S3_BUCKET_NAME="$AWS_S3_BUCKET_NAME" \
        --from-literal=AWS_S3_REGION="$AWS_S3_BUCKET_REGION" \
        --from-literal=CODEMIE_DOMAIN_NAME="$CODEMIE_DOMAIN_NAME" \
        > /dev/null

      # shellcheck disable=SC2181
      if [ $? -eq 0 ]; then
        log_message "success" "ConfigMap 'codemie-config' created successfully."
      else
        log_message "fail" "Failed to create ConfigMap 'codemie-config'."
        exit 1
      fi
    fi

    if ! check_k8s_secret_exists "$namespace" "codemie-cache"; then
      kubectl -n "$namespace" create secret generic "codemie-cache" \
        --from-literal=endpoint="${AWS_CACHE_ENDPOINT}" \
        --from-literal=secret="${AWS_CACHE_SECRET}" \
        --type=Opaque > /dev/null

      # shellcheck disable=SC2181
      if [ $? -eq 0 ]; then
        log_message "success" "Secret 'codemie-cache' created successfully."
      else
        log_message "fail" "Failed to create secret 'codemie-cache'."
        exit 1
      fi
    fi

    # Generate password for Sup
    if ! check_k8s_secret_exists "$namespace" "codemie-access"; then
      # Generate RSA KeyPair
      local private_key=$(openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 2>/dev/null)
      local public_key=$(echo "$private_key" | openssl rsa -pubout 2>/dev/null)

      kubectl -n "$namespace" create secret generic "codemie-access" \
        --from-literal=email="admin@codemie.ai" \
        --from-literal=password="$(openssl rand -base64 18)" \
        --from-literal=jwt_private.pem="$private_key" \
        --from-literal=jwt_public.pem="$public_key" \
        --type=Opaque > /dev/null

      # shellcheck disable=SC2181
      if [ $? -eq 0 ]; then
        log_message "success" "Secret 'codemie-access' created successfully."
      else
        log_message "fail" "Failed to create secret 'codemie-access'."
        exit 1
      fi
    fi

    log_message "info" "Deploying AI/Run API Helm Chart ..."
    helm upgrade --install codemie-api "$helm_repository" \
      --version "${ai_run_version}" \
      --namespace "$namespace" \
      -f "${values_file}" \
      --set "image.repository=$image_repository/codemie" \
      --set "image.tag=$ai_run_version-oss" \
      --set "serviceAccount.annotations.eks\.amazonaws\.com\/role-arn=${EKS_AWS_ROLE_ARN}" \
      --set "ingress.host=codemie.$CODEMIE_DOMAIN_NAME" \
      --wait \
      --timeout 600s \
      --dependency-update > /dev/null

    # shellcheck disable=SC2181
    if [ $? -eq 0 ]; then
        log_message "success" "AI/Run API deployment completed"
    else
        log_message "fail" "Failed to deploy AI/Run API."
        exit 1
    fi
}

deploy_codemie_mcp_connect_service() {
    local ai_run_version="$1"
    local image_repository="$2"
    local helm_repository="oci://$image_repository/codemie-mcp-connect-service"
    local namespace="codemie"

    log_message "info" "Starting CodeMie MCP Connect Service deployment."

    check_and_create_namespace "$namespace"

    log_message "info" "Deploying CodeMie MCP Connect Service Helm Chart ..."
    helm upgrade --install codemie-mcp-connect-service "$helm_repository" \
      --version "${ai_run_version}" \
      --namespace "$namespace" \
      --set "image.repository=$image_repository/codemie-mcp-connect-service" \
      --set "image.tag=$ai_run_version-oss" \
      --wait \
      --timeout 600s \
      --dependency-update > /dev/null

    # shellcheck disable=SC2181
    if [ $? -eq 0 ]; then
        log_message "success" "CodeMie MCP Connect Service deployment completed."
    else
        log_message "fail" "Failed to deploy CodeMie MCP Connect Service."
        exit 1
    fi
}

deploy_mermaid_server() {
    local ai_run_version="$1"
    local image_repository="$2"
    local values_file="./mermaid-server/values.yaml"
    local helm_repository="oci://$image_repository/mermaid-server"
    local namespace="codemie"

    log_message "info" "Starting Mermaid Server deployment."

    check_and_create_namespace "$namespace"

    log_message "info" "Deploying Mermaid Server Helm Chart ..."
    helm upgrade --install mermaid-server "$helm_repository" \
      --version "${ai_run_version}" \
      --namespace "$namespace" \
      -f "${values_file}" \
      --set "image.repository=$image_repository/mermaid-server" \
      --set "image.tag=$ai_run_version-oss" \
      --wait \
      --timeout 600s \
      --dependency-update > /dev/null

    # shellcheck disable=SC2181
    if [ $? -eq 0 ]; then
        log_message "success" "Mermaid Server deployment completed."
    else
        log_message "fail" "Failed to deploy Mermaid Server."
    fi
}

################
# Main Function
################

main() {
    echo "AI/Run CodeMie Helm Charts Deployment Script"
    echo "================================"

    exec > >(tee -a "$LOG_FILE") 2>&1

    check_helm
    check_nsc
    check_htpasswd

    load_deployment_env

    verify_inputs "$@"
    log_message "info" ""
    log_message "info" "version is set to '$ai_run_version'"
    log_message "info" ""

    verify_aws_login
    helm_registry_login
    configure_kubectl

    deploy_storage_class
    deploy_nginx_ingress_controller

    deploy_elasticsearch
    deploy_kibana "${CODEMIE_DOMAIN_NAME}"
    deploy_fluent_bit

    deploy_codemie_mcp_connect_service "$ai_run_version" "$image_repository"
    deploy_mermaid_server "$ai_run_version" "$image_repository"
    deploy_codemie_ui "$ai_run_version" "$image_repository" "${CODEMIE_DOMAIN_NAME}"
    deploy_codemie_api "$ai_run_version" "$image_repository" "${CODEMIE_DOMAIN_NAME}"

    print_summary
}

main "$@"
