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
    AWS_REGION     = 'ap-northeast-2' 
    ACCOUNT_ID     = '193491250091'
    ECR_IMAGE      = "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/mybalance-stg/app"

    // --- 태그 정책 ---
    IMAGE_TAG  = "${env.BUILD_NUMBER}"
    LATEST_TAG = "latest"

    // --- 배포 타깃(SSM: Name 태그) ---
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

    // --- [수정] Deploy 단계 ---
    stage('Deploy to EC2 via SSM') {
      steps {
        script {
          def targets = env.SSM_TARGETS.split(',')
          for (t in targets) {
            echo "Deploying to ${t} ..."

            // [수정] --parameters를 작은따옴표(') 대신 큰따옴표(")로 묶고
            // 내부의 모든 "를 \"로, $(hostname)을 \\$(hostname)으로 이스케이프
            sh """
            aws ssm send-command \
              --document-name "AWS-RunShellScript" \
              --comment "Deploy ${ECR_IMAGE}:${IMAGE_TAG} to ${t}" \
              --targets "Key=tag:Name,Values=${t}" \
              --parameters "{ \
                \"commands\": [ \
                  \"set -euxo pipefail\", \
                  \"echo --- Deploying on \\$(hostname) ---\", \
                  \
                  \"echo --- 2) ECR Logging in ---\", \
                  \"aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com\", \
                  \
                  \"echo --- 3) Preparing service directory ---\", \
                  \"sudo mkdir -p ${SERVICE_DIR}\", \
                  \"sudo chown ec2-user:ec2-user ${SERVICE_DIR}\", \
                  \"cd ${SERVICE_DIR}\", \
                  \
                  \"echo --- 4) Creating docker-compose.yml if not exists ---\", \
                  \"if [ ! -f docker-compose.yml ]; then\", \
                  \"cat > docker-compose.yml <<'EOF'\", \
                  \"version: '3.9'\", \
                  \"services:\", \
                  \"  ${SERVICE_NAME}:\", \
                  \"    image: ${ECR_IMAGE}:latest\", \
                  \"    restart: always\", \
                  \"    ports:\", \
                  \"      - '${HOST_PORT}:${CONTAINER_PORT}'\", \
                  \"    environment:\", \
                  \"      - TZ=${TZ}\", \
                  \"EOF\", \
                  \"fi\", \
                  \
                  \"echo --- 5) Pulling new image and restarting service ---\", \
                  \"docker compose pull\", \
                  \"docker compose up -d --remove-orphans\", \
                  \"docker image prune -f\", \
                  \"echo --- Deployment on \\$(hostname) complete ---\" \
                ] \
              }" \
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