pipeline {
  agent any
  options { timestamps() }

  environment {
    // --- Git ---
    GIT_REPO_URL    = 'https://github.com/kjis256/nginx-test'
    GIT_BRANCH      = 'main'
    DOCKERFILE_PATH = 'Dockerfile'
    BUILD_CONTEXT   = '.'

    // --- AWS/ECR ---
    AWS_REGION  = 'ap-northeast-2'
    ACCOUNT_ID  = '193491250091'
    // 전체 경로 포함 이미지 이름
    ECR_IMAGE   = "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/mybalance-stg/app"

    // --- 태그 정책 ---
    IMAGE_TAG   = "${env.BUILD_NUMBER}"
    LATEST_TAG  = "latest"

    // --- 배포 타깃(SSM: Name 태그) ---
    SSM_TARGETS = 'mybalance-stg-app01,mybalance-stg-app02'

    // --- 런타임 설정 ---
    SERVICE_NAME   = 'app'
    SERVICE_DIR    = '/srv/mybalance-app'
    CONTAINER_PORT = '80'
    HOST_PORT      = '80'
    TZ             = 'Asia/Seoul'
  }

  stages {
    stage('Checkout') {
      steps {
        git branch: env.GIT_BRANCH, url: env.GIT_REPO_URL
      }
    }

    stage('Docker Build') {
      steps {
        sh '''
          docker build -f "${DOCKERFILE_PATH}" -t "${ECR_IMAGE}:${IMAGE_TAG}" "${BUILD_CONTEXT}"
          docker tag "${ECR_IMAGE}:${IMAGE_TAG}" "${ECR_IMAGE}:${LATEST_TAG}"
        '''
      }
    }

    stage('ECR Login & Push') {
      steps {
        sh '''
          aws ecr get-login-password --region "${AWS_REGION}" \
            | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

          docker push "${ECR_IMAGE}:${IMAGE_TAG}"
          docker push "${ECR_IMAGE}:${LATEST_TAG}"
        '''
      }
    }

stage('Deploy to EC2 via SSM') {
  steps {
    script {
      def targets = env.SSM_TARGETS.split(',')
      for (t in targets) {
        echo "Deploying to ${t} ..."

        // 100자 제한 대응: 짧은 코멘트
        def shortComment = "Deploy ${env.SERVICE_NAME}:${env.IMAGE_TAG} -> ${t}"
        if (shortComment.length() > 99) {
          shortComment = shortComment.take(99)
        }

        // 1) SSM 명령 전송 + CommandId 획득
        def cmdId = sh(
          script: '''
            aws ssm send-command \
              --document-name "AWS-RunShellScript" \
              --comment "''' + shortComment + '''" \
              --targets "Key=tag:Name,Values=''' + t + '''" \
              --parameters commands=["set -euxo pipefail",\
"echo --- Deploying on \\$(hostname) ---",\
"aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com",\
"mkdir -p ${SERVICE_DIR}",\
"cd ${SERVICE_DIR}",\
"docker pull ${ECR_IMAGE}:${LATEST_TAG}",\
"(docker stop ${SERVICE_NAME} || true)",\
"(docker rm ${SERVICE_NAME} || true)",\
"docker run -d --name ${SERVICE_NAME} -p ${HOST_PORT}:${CONTAINER_PORT} -e TZ=${TZ} --restart always ${ECR_IMAGE}:${LATEST_TAG}",\
"docker image prune -f",\
"echo --- Deployment on \\$(hostname) complete ---"] \
              --region "${AWS_REGION}" \
              --query "Command.CommandId" \
              --output text
          ''',
          returnStdout: true
        ).trim()

        echo "SSM CommandId: ${cmdId}"

        // 2) 태그(Name) -> InstanceId 해석 (고유 Name 가정)
        def instanceId = sh(
          script: '''
            aws ec2 describe-instances \
              --filters "Name=tag:Name,Values=''' + t + '''" "Name=instance-state-name,Values=running" \
              --query "Reservations[].Instances[].InstanceId" \
              --output text \
              --region "${AWS_REGION}"
          ''',
          returnStdout: true
        ).trim()

        if (!instanceId) {
          error "인스턴스를 찾을 수 없습니다: ${t}"
        }
        echo "Target InstanceId: ${instanceId}"

        // 3) 상태 폴링 (Pending/InProgress/Delayed -> 완료까지 대기)
        sh '''
          set -euo pipefail
          STATUS="Pending"
          ATTEMPTS=0
          MAX_ATTEMPTS=180   # 최대 15분 (5s * 180)

          while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
            STATUS=$(aws ssm list-command-invocations \
              --command-id "''' + cmdId + '''" \
              --instance-id "''' + instanceId + '''" \
              --details \
              --query "CommandInvocations[0].Status" \
              --output text \
              --region "${AWS_REGION}" || echo "Unknown")

            case "$STATUS" in
              Pending|InProgress|Delayed)
                sleep 5
                ATTEMPTS=$((ATTEMPTS+1))
                ;;
              Success)
                echo "[OK] SSM 성공 (${STATUS})"
                # 표준출력/표준에러 출력
                aws ssm get-command-invocation \
                  --command-id "''' + cmdId + '''" \
                  --instance-id "''' + instanceId + '''" \
                  --region "${AWS_REGION}" \
                  --query "{StandardOutputContent:StandardOutputContent, StandardErrorContent:StandardErrorContent}" \
                  --output json
                exit 0
                ;;
              Cancelled|TimedOut|Failed|Cancelling)
                echo "[ERR] SSM 실패 (${STATUS})"
                aws ssm get-command-invocation \
                  --command-id "''' + cmdId + '''" \
                  --instance-id "''' + instanceId + '''" \
                  --region "${AWS_REGION}" \
                  --query "{StandardOutputContent:StandardOutputContent, StandardErrorContent:StandardErrorContent}" \
                  --output json || true
                exit 1
                ;;
              *)
                echo "[WARN] 알 수 없는 상태: $STATUS"
                sleep 5
                ATTEMPTS=$((ATTEMPTS+1))
                ;;
            esac
          done

          echo "[ERR] SSM 대기 타임아웃"
          exit 1
        '''
      }
    }
  }
}



  }

  post {
    success {
      echo "✅ 성공: ${ECR_IMAGE}:${IMAGE_TAG} 배포 완료"
    }
    failure {
      echo "❌ 실패: 로그 확인 필요"
    }
    always {
      sh '''
        docker logout "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com" || true
      '''
    }
  }
}
