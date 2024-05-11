pipeline {
    agent any
    stages {
        stage('Lint'){
            steps {
                sh 'terraform fmt'
            }
        }

        //stage('Security Check'){
        //   steps{
        //        sh 'snyk iac test .'
        //    }
        //}

        stage('Validation'){
            steps {
                sh 'terraform init'
                sh 'terraform validate'
            }
        }

        stage('Plan'){
            steps {
                sh 'bash -c "source /.connection.env && terraform plan -out=plan.tfplan"'
            }
        }

        stage('Move Plan'){
            steps {
                sh 'mv plan.tfplan /cd'
            }
        }
    }

    post {
        always {
            echo 'Cleaning up...'
            sh 'rm -rf *.tf *.tfplan'
        }

        success {
            echo 'All checks passed!'
        }

        failure {
            echo 'Notifying the team...'
        }
    }
}
