pipeline {
  agent any
  options { timestamps() }

  environment {
    // --- Git ---
    GIT_REPO_URL   = 'https://github.com/kjis256/nginx-test'
    GIT_BRANCH     = 'main'
    DOCKERFILE_PATH = 'Dockerfile'
    BUILD_CONTEXT   = '.'

    // --- AWS/ECR ---
    // [수정] AWS_DEFAULT_REGION -> AWS_REGION 으로 통일
    AWS_REGION     = 'ap-northeast-2' 
    ACCOUNT_ID     = '193491250091'
    
    // [수정] ECR_REPOSITORY 대신 ECR_IMAGE 변수명을 사용 (경로 전체 포함)
    ECR_IMAGE      = "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/mybalance-stg/app"

    // --- 태그 정책 ---
    IMAGE_TAG  = "${env.BUILD_NUMBER}"
    LATEST_TAG = "latest"

    // --- 배포 타깃(SSM: Name 태그) ---
    // [수정] Jenkinsfile과 Terraform의 태그가 일치해야 함 (was- 포함)
    SSM_TARGETS = 'mybalance-stg-was-newapp01,mybalance-stg-was-newapp02'

    // --- 원격 서버 런타임/Compose ---
    SERVICE_NAME   = 'app'
    SERVICE_DIR    = '/srv/mybalance-app'
    CONTAINER_PORT = '80'
    HOST_PORT      = '80'
    TZ = 'Asia/Seoul'
  }

  stages {
    stage('Checkout') {
      steps {
        git branch: env.GIT_BRANCH, url: env.GIT_REPO_URL
      }
    }

    stage('Docker Build') {
      steps {
        sh """
          docker build -f ${DOCKERFILE_PATH} -t ${ECR_IMAGE}:${IMAGE_TAG} ${BUILD_CONTEXT}
          docker tag ${ECR_IMAGE}:${IMAGE_TAG} ${ECR_IMAGE}:${LATEST_TAG}
        """
      }
    }

    stage('ECR Login & Push') {
      steps {
        sh """
          aws ecr get-login-password --region ${AWS_REGION} \
            | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

          docker push ${ECR_IMAGE}:${IMAGE_TAG}
          docker push ${ECR_IMAGE}:${LATEST_TAG}
        """
      }
    }

    stage('Deploy to EC2 via SSM') {
      steps {
        script {
          def targets = env.SSM_TARGETS.split(',')
          for (t in targets) {
            echo "Deploying to ${t} ..."

            // [수정] AWS_REGION 변수 사용, JSON 형식으로 변경
            sh """
            aws ssm send-command \
              --document-name "AWS-RunShellScript" \
              --comment "Deploy ${ECR_IMAGE}:${IMAGE_TAG} to ${t}" \
              --targets "Key=tag:Name,Values=${t}" \
              --parameters '{
                "commands": [
                  "set -euxo pipefail",
                  "echo --- Deploying on \$(hostname) ---",
                  
                  # 1) Docker 설치 (ssm_provision.tf가 이미 처리했으므로 제거)
                  # "if ! command -v docker >/dev/null 2>&1; then ... fi",

                  # 2) ECR 로그인 (AWS_REGION 변수 사용)
                  "aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com",

                  # 3) 서비스 디렉터리 준비 (ec2-user)
                  "sudo mkdir -p ${SERVICE_DIR}",
                  "sudo chown ec2-user:ec2-user ${SERVICE_DIR}",
                  "cd ${SERVICE_DIR}",

                  # 4) docker-compose.yml 자동 생성
                  "if [ ! -f docker-compose.yml ]; then",
                  "cat > docker-compose.yml <<'EOF'",
                  "version: '3.9'",
                  "services:",
                  "  ${SERVICE_NAME}:",
                  # [수정] ECR_IMAGE 변수를 직접 사용 (가장 큰 오류 지점)
                  "    image: ${ECR_IMAGE}:latest", 
                  "    restart: always",
                  "    ports:",
                  "      - '${HOST_PORT}:${CONTAINER_PORT}'",
                  "    environment:",
                  "      - TZ=${TZ}",
                  "EOF",
                  "fi",

                  # 5) 최신 이미지로 업데이트
                  "docker compose pull",
                  "docker compose up -d --remove-orphans",
                  "docker image prune -f",
                  "echo --- Deployment on \$(hostname) complete ---"
                ]
              }' \
              --max-errors 0 \
              --timeout-seconds 900 \
              --region ${AWS_REGION} \
              --output text > /dev/null
            """
          }
        }
      }
    }
  }

  post {
    success { echo "✅ 성공: ${ECR_IMAGE}:${IMAGE_TAG} 배포 완료" }
    failure { echo "❌ 실패: 로그 확인 필요" }
    always {
      sh "docker logout ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    }
  }
}