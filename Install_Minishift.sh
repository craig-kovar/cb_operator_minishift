#!/bin/sh
#=====================================================================#
#	Couchbase Minishift Demo Management Tool
#		@Author - Craig Kovar
#		@Date - 10/20/2018
#		@Version - 1.0
#=====================================================================#

trap onError ERR

function onError
{
	echo "Error detected, exiting..."
	trap - ERR
	exit 1
}

function log
{
	echo "[$1]"	
}

function logSection
{
	echo ""
	echo "[$1]"
	echo ""
}


#Constants
VERSION=1.0.0
user="none"
status="Stopped"

if [ ! -f CB_Minishift.properties ];then
	log "Unable to locate property file CB_Minishift.properties"
	exit 1
else
	. ./CB_Minishift.properties
	
fi

#--------------------------------------------------------------#
#	Functions
#--------------------------------------------------------------#
function check_prereq
{
	logSection "Checking prereqs..."
	fail=0
	if  ! type brew > /dev/null;then
		fail=1
		log "Home Brew is not installed"
	else
		log "Home Brew	... passed"
	fi
	
	if  ! type wget > /dev/null;then
		fail=1
		log "wget is not installed"
	else
		log "wget	... passed"
	fi
	
	if  ! type docker > /dev/null;then
		fail=1
		log "docker is not installed"
	else
		log "docker	... passed"
	fi

	if  ! type virtualbox > /dev/null;then
		fail=1
		log "virtualbox is not installed"
	else
		log "virtualbox	... passed"
	fi

	if [ $fail -ge 1 ];then
		log "Prerequisites did not pass...."
		exit 1
	fi

}

function login
{
	logSection "Logging in to OC cluster"
	if [ ! -z $OC_CLUSTER_LOC ];then
		log "Logging into $OC_CLUSTER_LOC"
		log "oc login $OC_CLUSTER_LOC"
		oc login $OC_CLUSTER_LOC

		DEPLOY_SOURCE=REMOTE
	fi	
}

function get_status
{
	logSection "Retrieving status...."
	if [ -z $OC_CLUSTER_LOC ];then
		status=`minishift status | grep Minishift | cut -d" " -f3`
	else
		status="Running"
		DEPLOY_SOURCE=REMOTE
	fi

	log "Checking status of : $DEPLOY_SOURCE"
	log "Current Status is : $status"
}

function verify_status
{
	get_status
	if [ "$status" != "Running" ];then
		log "Minishift is not running, exiting..."
		exit 1
	fi
}

function errPass
{
	log "Checking OC status"
}

function update_operator_yaml
{
	logSection "Updating $OPERATORYAML to docker image"
	YAML=$OPERATORYAML
	if [ ! -f $OPERATORYAML ];then
		if [ -f ${SNAME}/${OPERATORYAML} ];then
			YAML=${SNAME}/${OPERATORYAML}
		fi
	fi

	sed -i .`date +%Y%m%d%H%M%S`  -e "s|        image: .*|        image: $OPERATOR_IMAGE|g" $YAML
}

function update_cluster_yaml
{
	logSection "Updating $CBCLUSTERYAML to docker image"
	YAML=$CBCLUSTERYAML
	if [ ! -f $CBCLUSTERYAML ];then
		if [ -f ${SNAME}/${CBCLUSTERYAML} ];then
			YAML=${SNAME}/${CBCLUSTERYAML}
		fi
	fi

	sed -i .`date +%Y%m%d%H%M%S`  -e "s|  baseImage: .*|  baseImage: $CB_IMAGE|g" -e "s|  version: .*|  version: $CB_VERSION|g" $YAML
}

function checkOC
{
	trap - ERR
	trap errPass ERR
	if  ! type oc > /dev/null;then
		log "OC command not registered, run . ./Install_Minishift.sh set_env"
		trap - ERR
		exit 1
	fi

	log "OC is registered"
	trap - ERR
	trap onError ERR
}

function set_env
{
	get_status
	if [ "$status" = "Running" ];then
		eval $(minishift oc-env)
		log "OC is registered"
	else
		log "Minishift not running..."
	fi
}

function install_core
{
	check_prereq

	#Install Minishift
	logSection "Installing minishift...."
	brew cask install minishift

	#Download CB Autonomous Operator for MacOS
	logSection "Downloading CB Autonomous Operator"
	wget ${W3_LOC}/${CBOP_NAME}

	#UNZIP CB OP
	logSection "Unzipping CB Autonomous Operator"
	log "Running: unzip -o $CBOP_NAME"
	unzip -o $CBOP_NAME
	if [ $? -gt 0 ];then
		echo "Unable to unzip file"
	else
		rm $CBOP_NAME
	fi

	#Change to directory
	#logSection "CDing to CB Operator Directory"
	#cd $SNAME
	#log "At directory:  `pwd`"

	#Starting Minishift
	logSection "Starting minishift...."
	minishift start --vm-driver=virtualbox --cpus $CPU_CNT --memory $MEMORY

	#Applying admin addon to minishift
	logSection "Applying minishift addon admin-user"
	minishift addon apply admin-user	

	#Set up OC command
	logSection "Setting up OC command"
	echo ""
	eval $(minishift oc-env)
}

function start_minishift
{
	logSection "Starting Minishift"

	get_status

	if [[ "$status" = "Stopped" || -z $status ]];then
		log "Starting minishift...."
		minishift start --vm-driver=virtualbox --cpus $CPU_CNT --memory $MEMORY
		
		log "Setting up OC command line"
        	eval $(minishift oc-env)
		
		log "Applying minishift addon admin-user"
		minishift addon apply admin-user	
	fi
}


function stopMinishift
{
	logSection "Stopping Minishift"
	get_status
	if [ "$status" = "Running" ];then
		log "Stopping minishift...."
		minishift stop
	fi
}

function create_project
{
	#Login as developer
	logSection "Creating an OpenShift Project"

	if [ "$DEPLOY_SOURCE" = "MINISHIFT" ];then
		log "Logging in as Developer"
		oc logout
		oc login --insecure-skip-tls-verify -u developer <<< "developer"
	fi

	proj_cnt=`oc get project | grep -c ${OC_PROJ_NAME}`
	if [ $proj_cnt -gt 0 ];then
		log "Running: oc delete project ${OC_PROJ_NAME}"
		oc delete project ${OC_PROJ_NAME}
		sleep $SLEEP_DELAY
	fi

	log "Creating new project: $OC_PROJ_NAME"
	oc new-project ${OC_PROJ_NAME}

	#log "Logging out"
	#oc logout
}

function get_user
{
	logSection "Retrieving User...."
	log "Checking minishift status"
	get_status
	if [ "$status" = "Running" ];then
		user=`oc whoami | awk '{print $1}'`
		log "Current user is : $user"
	else
		log "Minishift is not running"
		exit 1
	fi
}

function install_crd
{
	logSection "Deploying Couchbase CRD"
	get_user
	if [[ "$user" = "developer"  && "$DEPLOY_SOURCE" = "MINISHIFT" ]];then
		log "User [$user] has insufficient priveleges to install CRD, switching to admin"
		oc logout
		oc login --insecure-skip-tls-verify -u admin <<< "admin"
	fi

	#TODO add check if already deployed,  then remove and deploy
	crd_count=`oc get crd | grep -c "couchbaseclusters.couchbase.com"`
	
	if [ $crd_count -gt 0 ];then
		if [ -f $CRDYAML ];then
			log "Running: oc replace -f $CRDYAML"
			oc replace -f $CRDYAML
		elif [ -f $SNAME/$CRDYAML ];then
			log "Running: oc replace -f $SNAME/$CRDYAML"
			oc replace -f $SNAME/$CRDYAML
		else
			log "Unable to locate $CRDYAML, exiting..."
			exit 1
		fi
	else
		if [ -f $CRDYAML ];then
			log "Running: oc create -f $CRDYAML"
			oc create -f $CRDYAML
		elif [ -f $SNAME/$CRDYAML ];then
			log "Running: oc create -f $SNAME/$CRDYAML"
			oc create -f $SNAME/$CRDYAML
		else
			log "Unable to locate $CRDYAML, exiting..."
			exit 1
		fi
	fi
}

function create_rh_secret {
	logSection "Creating RedHat secret..."

	get_user
	if [[ "$user" = "developer" && "$DEPLOY_SOURCE" = "MINISHIFT" ]];then
                log "User [$user] has insufficient priveleges to install CRD, switching to admin"
                oc logout
                oc login --insecure-skip-tls-verify -u admin <<< "admin"
        fi	

	sec_count=`oc get secret --namespace $OC_PROJ_NAME | grep -c "$RH_SECRET"`
	
	if [ "$status" = "Running" ];then
		if [ "$sec_count" -gt 0 ];then
			log "Running oc replace secret...."
			oc delete secret $RH_SECRET --namespace $OC_PROJ_NAME
			sleep $SLEEP_DELAY
			oc create secret docker-registry $RH_SECRET --docker-server=registry.connect.redhat.com \
 		 	--docker-username=$RH_USER --docker-password=$RH_PASSWORD --docker-email=$RH_EMAIL --namespace $OC_PROJ_NAME
		else
			log "Running oc create secret..."
			oc create secret docker-registry $RH_SECRET --docker-server=registry.connect.redhat.com \
 		 	--docker-username=$RH_USER --docker-password=$RH_PASSWORD --docker-email=$RH_EMAIL --namespace $OC_PROJ_NAME
		fi
	fi
}

function create_object {

	OBJECT=${1}
	NAMESPACE=${2}

	if [ "$status" = "Running" ];then
		if [ -f $OBJECT ];then
			if [ ! -z $NAMESPACE ];then
				log "Running: oc create -f $OBJECT -n $NAMESPACE"
				oc create -f $OBJECT -n $NAMESPACE
			else
				log "Running: oc create -f $OBJECT"
				oc create -f $OBJECT
			fi
		elif [ -f $SNAME/$OBJECT ];then
			if [ ! -z $NAMESPACE ];then
				log "Running: oc create -f $SNAME/$OBJECT -n $NAMESPACE"
				oc create -f $SNAME/$OBJECT -n $NAMESPACE
			else
				log "Running: oc create -f $SNAME/$OBJECT"
				oc create -f $SNAME/$OBJECT
			fi
		else
			log "Unable to locate $OBJECT"
			exit 1
		fi
	else
		log "Minishift is not running...."
		exit 1
	fi
}

function delete_object {

	OBJECT=${1}
	NAMESPACE=${2}

	if [ "$status" = "Running" ];then
		if [ -f $OBJECT ];then
			if [ ! -z $NAMESPACE ];then
				log "Running: oc delete -f $OBJECT -n $NAMESPACE"
				oc delete -f $OBJECT -n $NAMESPACE
			else
				log "Running: oc delete -f $OBJECT"
				oc delete -f $OBJECT
			fi
		elif [ -f $SNAME/$OBJECT ];then
			if [ ! -z $NAMESPACE ];then
				log "Running: oc delete -f $SNAME/$OBJECT -n $NAMESPACE"
				oc delete -f $SNAME/$OBJECT -n $NAMESPACE
			else
				log "Running: oc delete -f $SNAME/$OBJECT"
				oc delete -f $SNAME/$OBJECT
			fi
		else
			log "Unable to locate $OBJECT"
			exit 1
		fi
	else
		log "Minishift is not running...."
		exit 1
	fi
}

function kube_create_object {

	OBJECT=${1}
	NAMESPACE=${2}

	if [ "$status" = "Running" ];then
		if [ -f $OBJECT ];then
			if [ ! -z $NAMESPACE ];then
				log "Running: kubectl create -f $OBJECT -n $NAMESPACE"
				kubectl create -f $OBJECT -n $NAMESPACE
			else
				log "Running: kubectl create -f $OBJECT"
				kubectl create -f $OBJECT
			fi
		elif [ -f $SNAME/$OPERATORYAML ];then
			if [ ! -z $NAMESPACE ];then
				log "Running: kubectl create -f $SNAME/$OBJECT -n $NAMESPACE"
				kubectl create -f $SNAME/$OBJECT -n $NAMESPACE
			else
				log "Running: kubectl create -f $SNAME/$OBJECT"
				kubectl create -f $SNAME/$OBJECT
			fi
		else
			log "Unable to locate $OBJECT"
			exit 1
		fi
	else
		log "Minishift is not running...."
		exit 1
	fi
}

function kube_delete_object {

	OBJECT=${1}
	NAMESPACE=${2}

	if [ "$status" = "Running" ];then
		if [ -f $OBJECT ];then
			if [ ! -z $NAMESPACE ];then
				log "Running: kubectl delete -f $OBJECT -n $NAMESPACE"
				kubectl delete -f $OBJECT -n $NAMESPACE
			else
				log "Running: kubectl delete -f $OBJECT"
				kubectl delete -f $OBJECT
			fi
		elif [ -f $SNAME/$OPERATORYAML ];then
			if [ ! -z $NAMESPACE ];then
				log "Running: kubectl delete -f $SNAME/$OBJECT -n $NAMESPACE"
				kubectl delete -f $SNAME/$OBJECT -n $NAMESPACE
			else
				log "Running: kubectl delete -f $SNAME/$OBJECT"
				kubectl delete -f $SNAME/$OBJECT
			fi
		else
			log "Unable to locate $OBJECT"
			exit 1
		fi
	else
		log "Minishift is not running...."
		exit 1
	fi
}

function create_operator {
	logSection "Creating the operator"
	
	get_user
	if [[ "$user" != "developer" && "$DEPLOY_SOURCE" = "MINISHIFT" ]];then
                log "Switching from $user to developer"
                oc logout
                oc login --insecure-skip-tls-verify -u developer <<< "developer"
        fi
	
	if [ "$status" = "Running" ];then
		opcnt=`oc get deployments -l app=$OPERATOR_NAME --namespace $OC_PROJ_NAME | grep -c $OPERATOR_NAME`
		if [ "$opcnt" -gt 0 ];then
			log "Running: oc delete deployment -l app=$OPERATOR_NAME --namespace $OC_PROJ_NAME"
			oc delete deployment -l app=$OPERATOR_NAME --namespace $OC_PROJ_NAME
			sleep $SLEEP_DELAY
		fi

		if [ "$IMAGE_SOURCE" = "DOCKER" ];then
			update_operator_yaml
		elif [ "$IMAGE_SOURCE" = "REDHAT" ];then
			log "Image source = RedHat, nothing to do"
		else
			log "Unknown Image Source: $IMAGE_SOURCE, exiting..."
			exit 1
		fi

		if [ -f $OPERATORYAML ];then
			log "Running: oc create -f $OPERATORYAML -n $OC_PROJ_NAME"
			oc create -f $OPERATORYAML -n $OC_PROJ_NAME
		elif [ -f $SNAME/$OPERATORYAML ];then
			log "Running: oc create -f $SNAME/$OPERATORYAML -n $OC_PROJ_NAME"
			oc create -f $SNAME/$OPERATORYAML -n $OC_PROJ_NAME
		else
			log "Unable to locate $OPERATORYMAL"
			exit 1
		fi
	else
		log "Minishift is not running...."
		exit 1
	fi

	RETRY_CNT=1
	SUCC_CNT=0
	while [[ $SUCC_CNT -lt 1 && $RETRY_CNT -le $MAX_RETRY ]];do
		log "checking operator status... try $RETRY_CNT"
		SUCC_CNT=`oc get pods -l app=$OPERATOR_NAME | grep -c "1/1"`
		RETRY_CNT=$((RETRY_CNT+1))
		sleep $RETRY_DELAY
	done

	if [ $SUCC_CNT -lt 1 ];then
		log "Operator did not start..."
		exit 1
	fi
}

function create_cluster_role {
	logSection "Creating the cluster role"
	
	get_user
	if [[ "$user" = "developer" && "$DEPLOY_SOURCE" = "MINISHIFT" ]];then
                log "User [$user] has insufficient priveleges to install CRD, switching to admin"
                oc logout
                oc login --insecure-skip-tls-verify -u admin <<< "admin"
        fi
	
	if [ "$status" = "Running" ];then
		cr_count=`oc get clusterroles | grep -c "$CLUSTER_ROLE_NAME"`
		if [ "$cr_count" -gt 0 ];then
			delete_object $CLUSTERROLEYAML
			sleep $SLEEP_DELAY
		fi
		create_object $CLUSTERROLEYAML
	else
		log "Minishift is not running...."
		exit 1
	fi
}

function create_service_account {
	logSection "Creating the service account"
	
	get_user
	if [[ "$user" = "developer" && "$DEPLOY_SOURCE" = "MINISHIFT" ]];then
                log "User [$user] has insufficient priveleges to install CRD, switching to admin"
                oc logout
                oc login --insecure-skip-tls-verify -u admin <<< "admin"
        fi
	
	if [ "$status" = "Running" ];then
		sa_count=`oc get serviceaccounts --namespace $OC_PROJ_NAME | grep -c "$SVC_ACCOUNT"`
		if [ "$sa_count" -gt 0 ];then
			log "Running: oc delete serviceaccount $SVC_ACCOUNT --namespace $OC_PROJ_NAME"
			oc delete serviceaccount $SVC_ACCOUNT --namespace $OC_PROJ_NAME
			sleep $SLEEP_DELAY
		fi
		log "Running: oc create serviceaccount $SVC_ACCOUNT --namespace $OC_PROJ_NAME"
		oc create serviceaccount $SVC_ACCOUNT --namespace $OC_PROJ_NAME
	else
		log "Minishift is not running...."
		exit 1
	fi
}

function bind_svc_account
{
	logSection "Binding the service account"

	get_user
	if [[ "$user" = "developer" && "$DEPLOY_SOURCE" = "MINISHIFT" ]];then
                log "User [$user] has insufficient priveleges to bind user, switching to admin"
                oc logout
                oc login --insecure-skip-tls-verify -u admin <<< "admin"
        fi
	
	if [ "$status" = "Running" ];then
		log "Running: oc secrets link serviceaccount/$SVC_ACCOUNT secrets/$RH_SECRET --for=pull --namespace=$OC_PROJ_NAME"
		oc secrets link serviceaccount/$SVC_ACCOUNT secrets/$RH_SECRET --for=pull --namespace=$OC_PROJ_NAME

		log "Running: oc secrets link serviceaccount/default secrets/$RH_SECRET --for=pull --namespace=$OC_PROJ_NAME"
		oc secrets link serviceaccount/default secrets/$RH_SECRET --for=pull --namespace=$OC_PROJ_NAME

		crb_count=`oc get clusterrolebinding | grep -c "$CB_ROLE_BINDING"`
		if [ "$crb_count" -gt 0 ];then
			log "Running: oc delete clusterrolebinding $CB_ROLE_BINDING"
			oc delete clusterrolebinding $CB_ROLE_BINDING
			sleep $SLEEP_DELAY
		fi
		log "Running: oc create clusterrolebinding $CB_ROLE_BINDING --clusterrole $CLUSTER_ROLE_NAME --serviceaccount $OC_PROJ_NAME:$SVC_ACCOUNT"
		oc create clusterrolebinding $CB_ROLE_BINDING --clusterrole $CLUSTER_ROLE_NAME --serviceaccount $OC_PROJ_NAME:$SVC_ACCOUNT

		log "Running: oc adm policy add-scc-to-user anyuid system:serviceaccount:$OC_PROJ_NAME:$SVC_ACCOUNT"
		oc adm policy add-scc-to-user anyuid system:serviceaccount:$OC_PROJ_NAME:$SVC_ACCOUNT
	fi
		
}	


function create_user_role {
	logSection "Creating the user role"
	
	get_user
	if [[ "$user" = "developer" && "$DEPLOY_SOURCE" = "MINISHIFT" ]];then
                log "User [$user] has insufficient priveleges to install CRD, switching to admin"
                oc logout
                oc login --insecure-skip-tls-verify -u admin <<< "admin"
        fi
	
	if [ "$status" = "Running" ];then
		cr_count=`oc get clusterroles | grep -c "$CLUSTER_USER_NAME"`
		if [ "$cr_count" -gt 0 ];then
			delete_object $USERROLEYAML
			sleep $SLEEP_DELAY
		fi
		create_object $USERROLEYAML
	else
		log "Minishift is not running...."
		exit 1
	fi
}

function bind_user
{
	logSection "Binding the developer account"

	get_user
	if [[ "$user" = "developer" && "$DEPLOY_SOURCE" = "MINISHIFT" ]];then
                log "User [$user] has insufficient priveleges to bind user, switching to admin"
                oc logout
                oc login --insecure-skip-tls-verify -u admin <<< "admin"
        fi
	
	if [ "$status" = "Running" ];then
		
		crb_count=`oc get clusterrolebinding | grep -c "$CB_USER_BINDING"`
		if [ "$crb_count" -gt 0 ];then
			log "Running: oc delete clusterrolebinding $CB_USER_BINDING"
			oc delete clusterrolebinding $CB_USER_BINDING
			sleep $SLEEP_DELAY
		fi

		log "Running: oc create clusterrolebinding $CB_USER_BINDING --clusterrole $CLUSTER_USER_NAME --user developer"
		oc create clusterrolebinding $CB_USER_BINDING --clusterrole $CLUSTER_USER_NAME --user developer

	fi
}

function install_cbopctl
{
	logSection "Installing cbopctl tool..."

	if [[ -f ./bin/cbopctl || -f ${SNAME}/bin/cbopctl ]];then
		if [ -f /usr/local/bin/cbopctl ];then
			log "Removing old cbopctl"
			sudo rm /usr/local/bin/cbopctl
		fi

		if [ -f ./bin/cbopctl ];then
			log "Installing ./bin/cbopctl"
			chmod +x ./bin/cbopctl
			sudo mv ./bin/cbopctl /usr/local/bin/cbopctl
		else
			log "Installing ${SNAME}/bin/cbopctl"
			chmod +x ${SNAME}/bin/cbopctl
			sudo mv ${SNAME}/bin/cbopctl /usr/local/bin/cbopctl
		fi
	fi
}

function create_secret {
	logSection "Creating the CB user secret"
	
	get_status
	
	if [ "$status" = "Running" ];then
		cr_count=`oc get secret | grep -c "$SECRET_NAME"`
		if [ "$cr_count" -gt 0 ];then
			delete_object $SECRETYAML
			sleep $SLEEP_DELAY
		fi
		create_object $SECRETYAML
	else
		log "Minishift is not running...."
		exit 1
	fi
}

function full_rollback
{
	logSection "Performing a full rollback"
	
	get_user
	if [[ "$user" = "developer" && "$DEPLOY_SOURCE" = "MINISHIFT" ]];then
                log "User [$user] has insufficient priveleges to bind user, switching to admin"
                oc logout
                oc login --insecure-skip-tls-verify -u admin <<< "admin"
        fi
	
	if [ "$status" = "Running" ];then
		log "Verifying project"
		oc project $OC_PROJ_NAME		

		log "Removing cluster"
		count=`oc get couchbaseclusters | grep -c $CLUSTER_NAME`
		if [ $count -gt 0 ];then
			log "Running: oc delete couchbasecluster $CLUSTER_NAME"
			oc delete couchbasecluster $CLUSTER_NAME
		fi

		log "Removing route"
		count=`oc get routes | grep -c "${CLUSTER_NAME}-ui"`
		if [ $count -gt 0 ];then
			log "Running: oc delete route ${CLUSTER_NAME}-ui"
			oc delete route ${CLUSTER_NAME}-ui
		fi

		log "Removing secret"
		count=`oc get secrets | grep -c $SECRET_NAME`
		if [ $count -gt 0 ];then
			log "Running: oc delete secret $SECRET_NAME"
			oc delete secret $SECRET_NAME
		fi
		
		log "Removing operator"
		count=`oc get deployments | grep -c $OPERATOR_NAME`
		if [ $count -gt 0 ];then
			log "Running: oc delete deployment $OPERATOR_NAME"
			oc delete deployment $OPERATOR_NAME
		fi

		log "Removing developer cluster-role-binding"
		count=`oc get clusterrolebindings | grep -c $CB_USER_BINDING`
		if [ $count -gt 0 ];then
			log "Running: oc delete clusterrolebinding $CB_USER_BINDING"
			oc delete clusterrolebinding $CB_USER_BINDING
		fi

		log "Removing user cluster role"
		count=`oc get clusterrole | grep -c $CLUSTER_USER_NAME`
		if [ $count -gt 0 ];then
			log "Running: oc delete clusterrolebinding $CLUSTER_USER_NAME"
			oc delete clusterrole $CLUSTER_USER_NAME
		fi

		log "Removing SA cluster-role-binding"
		count=`oc get clusterrolebindings | grep -c $CB_ROLE_BINDING`
		if [ $count -gt 0 ];then
			log "Running: oc delete clusterrolebinding $CB_ROLE_BINDING"
			oc delete clusterrolebinding $CB_ROLE_BINDING
		fi

		log "Removing SA cluster role"
		count=`oc get clusterrole | grep -c $CLUSTER_ROLE_NAME`
		if [ $count -gt 0 ];then
			log "Running: oc delete clusterrolebinding $CLUSTER_ROLE_NAME"
			oc delete clusterrole $CLUSTER_ROLE_NAME
		fi

		
		log "Removing CRD"
		count=`oc get crd | grep -c "$CRD_NAME"`
		if [ $count -gt 0 ];then
			log "Running: oc delete crd $CRD_NAME"
			oc delete crd "$CRD_NAME"
		fi
		
		
		log "Removing Project"
		count=`oc get project | grep -c $OC_PROJ_NAME`
		if [ $count -gt 0 ];then
			log "Running: oc delete project $OC_PROJ_NAME"
			oc delete project $OC_PROJ_NAME
		fi
	
		stopMinishift	
	else
		log "Minishift not running"
	fi
}

function upsert_cluster
{
	logSection "Upserting couchbase cluster..."
	get_status
	
	if [ "$status" = "Running" ];then
		cr_count=`oc get couchbasecluster | grep -c "$CLUSTER_NAME"`
		
		if [ -f $CBCLUSTERYAML ];then
			CB_DEPLOY_NAME=$CBCLUSTERYAML
		elif [ -f ${SNAME}/${CBCLUSTERYAML} ];then
			CB_DEPLOY_NAME=${SNAME}/${CBCLUSTERYAML}
		else
			log "Unable to find $CBCLUSTERYAML..."
			exit 1
		fi
		
		if [ "$IMAGE_SOURCE" = "DOCKER" ];then
			update_cluster_yaml
		elif [ "$IMAGE_SOURCE" = "REDHAT" ];then
			log "Image source = RedHat, nothing to do"
		else
			log "Unknown Image Source: $IMAGE_SOURCE, exiting..."
			exit 1
		fi


		if [ "$cr_count" -gt 0 ];then
			log "Running: cbopctl apply -f $CB_DEPLOY_NAME"
			cbopctl apply -f $CB_DEPLOY_NAME
		else	
			log "Running: cbopctl create -f $CB_DEPLOY_NAME"
			cbopctl create -f $CB_DEPLOY_NAME
		fi
	else
		log "Minishift not running..."
		exit 1
	fi
}

function delete_cluster
{
	logSection "Deleting couchbase cluster..."
	get_status
	
	if [ "$status" = "Running" ];then
		cr_count=`oc get couchbasecluster | grep -c "$CLUSTER_NAME"`
		
		if [ -f $CBCLUSTERYAML ];then
			CB_DEPLOY_NAME=$CBCLUSTERYAML
		elif [ -f ${SNAME}/${CBCLUSTERYAML} ];then
			CB_DEPLOY_NAME=${SNAME}/${CBCLUSTERYAML}
		else
			log "Unable to find $CBCLUSTERYAML..."
			exit 1
		fi

		if [ "$cr_count" -gt 0 ];then
			log "Running: cbopctl delete -f $CB_DEPLOY_NAME"
			cbopctl delete -f $CB_DEPLOY_NAME
		else	
			log "No couchbase cluster named $CLUSTER_NAME detected..."
		fi
	else
		log "Minishift not running..."
		exit 1
	fi
}

function create_accounts
{
	logSection "Creating accounts"

	start_minishift

	create_rh_secret

	create_cluster_role

	create_service_account

	bind_svc_account

	create_user_role

	bind_user
}


function full_deploy
{
	logSection "Performing a full deployment"

	start_minishift

	create_project

	install_crd

	create_accounts

	create_operator	

	install_cbopctl

	create_secret

	upsert_cluster

	get_admin_ui

	log "\n\nCheck oc get pods for status of cluster deployment"
	
}	

function get_admin_ui
{
	logSection "Retrieving the admin UI location..."
	get_status
	
	if [ "$status" = "Running" ];then
		cr_count=`oc get routes | grep -c "${CLUSTER_NAME}-ui"`
		if [ "$cr_count" -gt 0 ];then
			log "Running: oc get routes | grep $CLUSTER_NAME | tr -s ' '| cut -d' ' -f2"
			log "	ADMIN URL:	`oc get routes | grep "$CLUSTER_NAME" | tr -s ' '| cut -d' ' -f2`	"
		else	
			log "Running: oc expose service/${CLUSTER_NAME}-ui"
			oc expose service/${CLUSTER_NAME}-ui
			sleep $SLEEP_DELAY
			log "Running: oc get routes | grep $CLUSTER_NAME | tr -s ' '| cut -d' ' -f2"
			log "	ADMIN URL:	`oc get routes | grep "$CLUSTER_NAME" | tr -s ' '| cut -d' ' -f2`	"
		fi
	else
		log "Minishift not running..."
		exit 1
	fi
}


function setup_s2i
{
	logSection "Setting up S2I for Java applications"
	get_status
	
	if [ "$status" = "Running" ];then
		log "Running: oc import-image registry.access.redhat.com/redhat-openjdk-18/openjdk18-openshift --confirm"
		oc import-image registry.access.redhat.com/redhat-openjdk-18/openjdk18-openshift --confirm
	else
		log "Minishift is not running"
	fi
}

function deploy_twitter_api
{
	logSection "Deploying twitter-api"
	get_status
	
	if [ "$status" = "Running" ];then

		count=`oc get svc | grep -c twitter-api`
		if [ $count -eq 1 ];then
			log "Twitter API already deployed..."
			return 0
		fi

		log "\noc new-app registry.access.redhat.com/redhat-openjdk-18/openjdk18-openshift:latest~https://github.com/couchbase-partners/redhat-pds.git \
			\n\t-e COUCHBASE_CLUSTER=$CLUSTER_NAME \
			\n\t-e COUCHBASE_USER=$CB_USER \
			\n\t-e COUCHBASE_PASSWORD=$CB_PASS \
			\n\t-e COUCHBASE_TWEET_BUCKET=$CB_TWEET_BUCKET \
			\n\t--context-dir=cb-rh-twitter/twitter-api \
			\n\t--name=twitter-api\n"

		oc new-app registry.access.redhat.com/redhat-openjdk-18/openjdk18-openshift:latest~https://github.com/couchbase-partners/redhat-pds.git \
		-e COUCHBASE_CLUSTER=$CLUSTER_NAME \
		-e COUCHBASE_USER=$CB_USER \
		-e COUCHBASE_PASSWORD=$CB_PASS \
		-e COUCHBASE_TWEET_BUCKET=$CB_TWEET_BUCKET \
		--context-dir=cb-rh-twitter/twitter-api \
		--name=twitter-api

	
		sleep $BUILD_RETRY_DELAY	
		RETRY_CNT=1
		SUCC_CNT=`oc logs bc/twitter-api | grep -c "BUILD SUCCESS"`
		PUSH_CNT=`oc logs bc/twitter-api | grep -c "Push successful"`
		while [[ $PUSH_CNT -lt 1 && $SUCC_CNT -lt 1 && $RETRY_CNT -le $BUILD_RETRY ]];do
			log "checking twitter-api status... try $RETRY_CNT"
			SUCC_CNT=`oc logs bc/twitter-api | grep -c "BUILD SUCCESS"`
			PUSH_CNT=`oc logs bc/twitter-api | grep -c "Push successful"`
			RETRY_CNT=$((RETRY_CNT+1))
			sleep $BUILD_RETRY_DELAY
		done

		if [[ $SUCC_CNT -lt 1 || $PUSH_CNT -lt 1 ]];then
			log "Build Success = $SUCC_CNT"
			log "Push Success = $PUSH_CNT"
			log "Failed to build|push application"
			exit 1
		fi

		log "Exposing the twitter-api service:  oc expose svc twitter-api"
		oc expose svc twitter-api
	else
		log "Minishift is not running"
	fi
}

function remove_twitter_api
{
	logSection "Removing twitter-api"
	get_status
	
	if [ "$status" = "Running" ];then
		log "Removing twitter-api service"
		count=`oc get svc | grep -c twitter-api`
		if [ $count -eq 1 ];then
			log "Running: oc delete svc twitter-api"
			oc delete svc twitter-api
		fi

		log "Removing twitter-api deploymentconfig"
		count=`oc get dc | grep -c twitter-api`
		if [ $count -eq 1 ];then
			log "Running: oc delete dc twitter-api"
			oc delete dc twitter-api
		fi

		log "Removing twitter-api buildconfig"
		count=`oc get bc | grep -c twitter-api`
		if [ $count -eq 1 ];then
			log "Running: oc delete bc twitter-api"
			oc delete bc twitter-api
		fi

		log "Removing twitter-api imagestream"
		count=`oc get is | grep -c twitter-api`
		if [ $count -eq 1 ];then
			log "Running: oc delete is twitter-api"
			oc delete is twitter-api
		fi

		log "Removing twitter-api route"
		count=`oc get routes | grep -c twitter-api`
		if [ $count -eq 1 ];then
			log "Running: oc delete route twitter-api"
			oc delete route twitter-api
		fi

	fi
}

function deploy_twitter_ui
{
	logSection "Deploying twitter-ui"
	get_status

	if [ "$status" = "Running" ];then

		count=`oc get svc | grep -c twitter-ui`
		if [ $count -eq 1 ];then
			log "Twitter UI already deployed..."
			return 0
		fi

		log "Running: oc new-app ezeev/twitter-ui:latest"
		oc new-app ezeev/twitter-ui:latest

		log "Exposing the twitter-ui service:  oc expose svc twitter-ui"
		oc expose svc twitter-ui
	else
		log "Minishift is not running"
	fi
}

function remove_twitter_ui
{
	logSection "Removing twitter-ui"
	get_status
	
	if [ "$status" = "Running" ];then
		log "Removing twitter-ui service"
		count=`oc get svc | grep -c twitter-ui`
		if [ $count -eq 1 ];then
			log "Running: oc delete svc twitter-ui"
			oc delete svc twitter-ui
		fi

		log "Removing twitter-ui deploymentconfig"
		count=`oc get dc | grep -c twitter-ui`
		if [ $count -eq 1 ];then
			log "Running: oc delete dc twitter-ui"
			oc delete dc twitter-ui
		fi

		log "Removing twitter-ui buildconfig"
		count=`oc get bc | grep -c twitter-ui`
		if [ $count -eq 1 ];then
			log "Running: oc delete bc twitter-ui"
			oc delete bc twitter-ui
		fi

		log "Removing twitter-ui imagestream"
		count=`oc get is | grep -c twitter-ui`
		if [ $count -eq 1 ];then
			log "Running: oc delete is twitter-ui"
			oc delete is twitter-ui
		fi

		log "Removing twitter-ui route"
		count=`oc get routes | grep -c twitter-ui`
		if [ $count -eq 1 ];then
			log "Running: oc delete route twitter-ui"
			oc delete route twitter-ui
		fi

	fi
}

function get_twitter_ui
{
	logSection "Retrieving the twitter UI location..."
	get_status
	
	if [ "$status" = "Running" ];then
		cr_count=`oc get routes | grep -c "twitter-ui"`
		if [ "$cr_count" -gt 0 ];then
			log "Running: oc get routes | grep twitter-ui | tr -s ' '| cut -d' ' -f2"
			log "	ADMIN URL:	`oc get routes | grep twitter-ui | tr -s ' '| cut -d' ' -f2`	"
		fi
	else
		log "Minishift not running..."
		exit 1
	fi
}

function deploy_twitter_streamer
{
	logSection "Deploy twitter streamer"
	get_status

	if [ "$status" = "Running" ];then

		cr_count=`oc get svc | grep -c "twitter-streamer"`
		if [ $cr_count -eq 0 ];then
	
			log "\nRunning: oc new-app registry.access.redhat.com/redhat-openjdk-18/openjdk18-openshift:latest~https://github.com/couchbase-partners/redhat-pds.git \
			\n\t-e TWITTER_CONSUMER_KEY=$TWITTER_CONSUMER_KEY \
			\n\t-e TWITTER_CONSUMER_SECRET=$TWITTER_CONSUMER_SECRET \
			\n\t-e TWITTER_TOKEN=$TWITTER_ACCESS_TOKEN \
			\n\t-e TWITTER_SECRET=$TWITTER_ACCESS_SECRET \
			\n\t-e TWITTER_FILTER=\"$TWITTER_FILTER\" \
			\n\t-e COUCHBASE_CLUSTER=$CLUSTER_NAME \
			\n\t-e COUCHBASE_USER=$CB_USER \
			\n\t-e COUCHBASE_PASSWORD=$CB_PASS \
			\n\t-e COUCHBASE_TWEET_BUCKET=$CB_TWEET_BUCKET \
			--context-dir=cb-rh-twitter/twitter-streamer \
			--name=twitter-streamer\n"		
	
			oc new-app registry.access.redhat.com/redhat-openjdk-18/openjdk18-openshift:latest~https://github.com/couchbase-partners/redhat-pds.git \
      			 -e TWITTER_CONSUMER_KEY=$TWITTER_CONSUMER_KEY \
       			 -e TWITTER_CONSUMER_SECRET=$TWITTER_CONSUMER_SECRET \
       			 -e TWITTER_TOKEN=$TWITTER_ACCESS_TOKEN \
      			 -e TWITTER_SECRET=$TWITTER_ACCESS_SECRET \
      			 -e TWITTER_FILTER="$TWITTER_FILTER" \
      			 -e COUCHBASE_CLUSTER=$CLUSTER_NAME \
      			 -e COUCHBASE_USER=$CB_USER \
      			 -e COUCHBASE_PASSWORD=$CB_PASS \
      			 -e COUCHBASE_TWEET_BUCKET=$CB_TWEET_BUCKET \
      			 --context-dir=cb-rh-twitter/twitter-streamer \
      			 --name=twitter-streamer
		

			sleep $BUILD_RETRY_DELAY	
			RETRY_CNT=1
			SUCC_CNT=`oc logs bc/twitter-streamer | grep -c "BUILD SUCCESS"`
			PUSH_CNT=`oc logs bc/twitter-streamer | grep -c "Push successful"`
			while [[ $PUSH_CNT -lt 1 && $SUCC_CNT -lt 1 && $RETRY_CNT -le $BUILD_RETRY ]];do
				log "checking twitter-streamer status... try $RETRY_CNT"
				SUCC_CNT=`oc logs bc/twitter-streamer | grep -c "BUILD SUCCESS"`
				PUSH_CNT=`oc logs bc/twitter-streamer | grep -c "Push successful"`
				RETRY_CNT=$((RETRY_CNT+1))
				sleep $BUILD_RETRY_DELAY
			done

			if [[ $SUCC_CNT -lt 1 || $PUSH_CNT -lt 1 ]];then
				log "Build Success = $SUCC_CNT"
				log "Pushi Success = $PUSH_CNT"
				log "Failed to build|push application"
				exit 1
			fi

			log "Exposing the twitter-streamer service:  oc expose svc twitter-streamer"
			oc expose svc twitter-streamer
		else
			log "Twitter Streamer already detected, run remove_twitter_streamer before re-deploying"
		fi
	else
		log "Minishift is not running"
	fi
}

function remove_twitter_streamer
{
	logSection "Removing twitter-streamer"
	get_status
	
	if [ "$status" = "Running" ];then
		log "Removing twitter-streamer service"
		count=`oc get svc | grep -c twitter-streamer`
		if [ $count -eq 1 ];then
			log "Running: oc delete svc twitter-streamer"
			oc delete svc twitter-streamer
		fi

		log "Removing twitter-streamer deploymentconfig"
		count=`oc get dc | grep -c twitter-streamer`
		if [ $count -eq 1 ];then
			log "Running: oc delete dc twitter-streamer"
			oc delete dc twitter-streamer
		fi

		log "Removing twitter-streamer buildconfig"
		count=`oc get bc | grep -c twitter-streamer`
		if [ $count -eq 1 ];then
			log "Running: oc delete bc twitter-streamer"
			oc delete bc twitter-streamer
		fi

		log "Removing twitter-streamer imagestream"
		count=`oc get is | grep -c twitter-streamer`
		if [ $count -eq 1 ];then
			log "Running: oc delete is twitter-streamer"
			oc delete is twitter-streamer
		fi

		log "Removing twitter-streamer route"
		count=`oc get routes | grep -c twitter-streamer`
		if [ $count -eq 1 ];then
			log "Running: oc delete route twitter-streamer"
			oc delete route twitter-streamer
		fi

	fi
}

function deploy_mysql
{
	logSection "Deploying MySQL DB"

	verify_status

		log "\n	oc new-app -e MYSQL_USER=$MYSQL_USER \
\n\t-e MYSQL_PASSWORD=$MYSQL_PASSWORD \
\n\t-e MYSQL_DATABASE=$MYSQL_DATABASE \
\n\t-e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD \
\n\t--name=${MYSQL_NAME} \
\n\tmysql:latest"

		oc new-app -e MYSQL_USER=$MYSQL_USER \
-e MYSQL_PASSWORD=$MYSQL_PASSWORD \
-e MYSQL_DATABASE=$MYSQL_DATABASE \
-e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD \
--name=${MYSQL_NAME} \
mysql:latest

	log "oc expose svc/${MYSQL_NAME}"
	oc expose svc/${MYSQL_NAME}

}

function deploy_postgres
{
	logSection "Deploying Postgres DB"

	verify_status

		
		log "\n	oc new-app -e POSTGRESQL_USER=$POSTGRESQL_USER \
\n\t-e POSTGRESQL_PASSWORD=$POSTGRESQL_PASSWORD \
\n\t-e POSTGRESQL_DATABASE=$POSTGRESQL_DATABASE \
--name=${POSTGRESQL_NAME} \
\n\topenshift/postgresql-92-centos7"


		oc new-app -e POSTGRESQL_USER=$POSTGRESQL_USER \
-e POSTGRESQL_PASSWORD=$POSTGRESQL_PASSWORD \
-e POSTGRESQL_DATABASE=$POSTGRESQL_DATABASE \
--name=${POSTGRESQL_NAME} \
openshift/postgresql-92-centos7

	log "oc expose svc/${POSTGRESQL_NAME}"
	oc expose svc/${POSTGRESQL_NAME}

}

function port_forward
{
	logSection "Forwarding ports"

	verify_status	

		log "Running oc port-forward -p cb-example-0000 8091:8091 8092:8092 8093:8093 8094:8094 8095:8095 8096:8096 11210:11210 11211:11211 &"
		oc port-forward cb-example-0000 8091:8091 8092:8092 8093:8093 8094:8094 8095:8095 8096:8096 11210:11210 11211:11211 &
}

function create_mysql_user
{
        logSection "Creating mysql user"

        verify_status

	MYSQL_NAME_TMP=`oc get pods | grep ${MYSQL_NAME} | grep -v deploy | cut -d' ' -f1`

        cp -fp ./resources/templates/create_user.sql.template ./resources/create_user.sql

        sed -e "s/###MYSQL_USER###/$MYSQL_USER/g" -e "s/###MYSQL_PASSWORD###/$MYSQL_PASSWORD/g" -i .bkup ./resources/create_user.sql

        log "oc cp ./resources/create_user.sql ${MYSQL_NAME_TMP}:/tmp/create_user.sql"
        oc cp ./resources/create_user.sql ${MYSQL_NAME_TMP}:/tmp/create_user.sql

        log "oc exec -it ${MYSQL_NAME_TMP} -- bash -c \"mysql -uroot -p${MYSQL_ROOT_PASSWORD} -h${MYSQL_NAME_TMP} < /tmp/create_user.sql\""
        oc exec -it ${MYSQL_NAME_TMP} -- bash -c "mysql -uroot -p${MYSQL_ROOT_PASSWORD} -h${MYSQL_NAME_TMP} < /tmp/create_user.sql"
}

function load_mysql_data
{
	logSection "Loading mysql data"

        verify_status

	MYSQL_NAME_TMP=`oc get pods | grep ${MYSQL_NAME} | grep -v deploy | cut -d' ' -f1`

        cp -fp ./resources/templates/mysql-db.sql.template ./resources/mysql-db.sql
        sed -e "s/###MYSQL_DATABASE###/$MYSQL_DATABASE/g" -i .bkup ./resources/mysql-db.sql

        cp -fp ./resources/templates/db.sql.template ./resources/db.sql
        sed -e "s/###MYSQL_DATABASE###/$MYSQL_DATABASE/g" -i .bkup ./resources/db.sql

        log "oc cp ./resources/mysql-db.sql ${MYSQL_NAME_TMP}:/tmp/mysql-db.sql"
        oc cp ./resources/mysql-db.sql ${MYSQL_NAME_TMP}:/tmp/mysql-db.sql

        log "oc cp ./resources/db.sql ${MYSQL_NAME_TMP}:/tmp/db.sql"
        oc cp ./resources/db.sql ${MYSQL_NAME_TMP}:/tmp/db.sql

        log "oc exec -it ${MYSQL_NAME_TMP} -- bash -c \"mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} -h${MYSQL_NAME_TMP} < /tmp/mysql-db.sql\""
        oc exec -it ${MYSQL_NAME_TMP} -- bash -c "mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} -h${MYSQL_NAME_TMP} < /tmp/mysql-db.sql"
        
	log "oc exec -it ${MYSQL_NAME_TMP} -- bash -c \"mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} -h${MYSQL_NAME_TMP} < /tmp/db.sql\""
        oc exec -it ${MYSQL_NAME_TMP} -- bash -c "mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} -h${MYSQL_NAME_TMP} < /tmp/db.sql"
}

function load_postgres_data
{
	logSection "Loading postgre data"

        verify_status

	POSTGRE_NAME_TMP=`oc get pods | grep ${POSTGRESQL_NAME} | grep -v deploy | cut -d' ' -f1`

        cp -fp ./resources/templates/postgresql-db.sql.template ./resources/postgresql-db.sql

        sed -e "s/###POSTGRESQL_SCHEMA###/$POSTGRESQL_SCHEMA/g" \
	-e "s/###POSTGRESQL_DATABASE###/$POSTGRESQL_DATABASE/g" \
	-e "s/###POSTGRESQL_USER###/$POSTGRESQL_USER/g" \
	-e "s/###POSTGRESQL_PASSWORD###/$POSTGRESQL_PASSWORD/g" \
	-i .bkup ./resources/postgresql-db.sql

        log "oc cp ./resources/postgresql-db.sql ${POSTGRE_NAME_TMP}:/tmp/postgresql-db.sql"
        oc cp ./resources/postgresql-db.sql ${POSTGRE_NAME_TMP}:/tmp/postgresql-db.sql

        log "oc exec -it ${POSTGRE_NAME_TMP} -- bash -c \"psql postgres postgres -d ${POSTGRESQL_DATABASE} -f /tmp/postgresql-db.sql\""
        oc exec -it ${POSTGRE_NAME_TMP} -- bash -c "psql postgres postgres -d ${POSTGRESQL_DATABASE} -f /tmp/postgresql-db.sql"
}

function remove_mysql
{
	logSection "Removing mysql"
	verify_status
	
	log "Removing ${MYSQL_NAME} service"
	count=`oc get svc | grep -c ${MYSQL_NAME}`
	if [ $count -eq 1 ];then
		log "Running: oc delete svc ${MYSQL_NAME}"
		oc delete svc ${MYSQL_NAME}
	fi

	log "Removing ${MYSQL_NAME} deploymentconfig"
	count=`oc get dc | grep -c ${MYSQL_NAME}`
	if [ $count -eq 1 ];then
		log "Running: oc delete dc ${MYSQL_NAME}"
		oc delete dc ${MYSQL_NAME}
	fi

	log "Removing ${MYSQL_NAME} buildconfig"
	count=`oc get bc | grep -c ${MYSQL_NAME}`
	if [ $count -eq 1 ];then
		log "Running: oc delete bc ${MYSQL_NAME}"
		oc delete bc ${MYSQL_NAME}
	fi

	log "Removing ${MYSQL_NAME} imagestream"
	count=`oc get is | grep -c ${MYSQL_NAME}`
	if [ $count -eq 1 ];then
		log "Running: oc delete is ${MYSQL_NAME}"
		oc delete is ${MYSQL_NAME}
	fi

	log "Removing ${MYSQL_NAME} route"
	count=`oc get routes | grep -c ${MYSQL_NAME}`
	if [ $count -eq 1 ];then
		log "Running: oc delete route ${MYSQL_NAME}"
		oc delete route ${MYSQL_NAME}
	fi
}

function remove_postgres
{
	logSection "Removing postgre"
	verify_status
	
	log "Removing ${POSTGRESQL_NAME} service"
	count=`oc get svc | grep -c ${POSTGRESQL_NAME}`
	if [ $count -eq 1 ];then
		log "Running: oc delete svc ${POSTGRESQL_NAME}"
		oc delete svc ${POSTGRESQL_NAME}
	fi

	log "Removing ${POSTGRESQL_NAME} deploymentconfig"
	count=`oc get dc | grep -c ${POSTGRESQL_NAME}`
	if [ $count -eq 1 ];then
		log "Running: oc delete dc ${POSTGRESQL_NAME}"
		oc delete dc ${POSTGRESQL_NAME}
	fi

	log "Removing ${POSTGRESQL_NAME} buildconfig"
	count=`oc get bc | grep -c ${POSTGRESQL_NAME}`
	if [ $count -eq 1 ];then
		log "Running: oc delete bc ${POSTGRESQL_NAME}"
		oc delete bc ${POSTGRESQL_NAME}
	fi

	log "Removing ${POSTGRESQL_NAME} imagestream"
	count=`oc get is | grep -c ${POSTGRESQL_NAME}`
	if [ $count -eq 1 ];then
		log "Running: oc delete is ${POSTGRESQL_NAME}"
		oc delete is ${POSTGRESQL_NAME}
	fi

	log "Removing ${POSTGRESQL_NAME} route"
	count=`oc get routes | grep -c ${POSTGRESQL_NAME}`
	if [ $count -eq 1 ];then
		log "Running: oc delete route ${POSTGRESQL_NAME}"
		oc delete route ${POSTGRESQL_NAME}
	fi
}

function setup_c360_bucket
{
	logSection "Setting up the Customer 360 Bucket"

	verify_status

	log "oc cp ./resources/cards.json ${C360_POD}:/tmp/cards.json"
	oc cp ./resources/cards.json ${C360_POD}:/tmp/cards.json

	log "oc exec -it ${C360_POD} -- bash -c \"/opt/couchbase/bin/cbimport json -c couchbase://cb-example-0000 -u ${CB_USER} -p ${CB_PASS} -b ${C360_BUCKET} -d file://tmp/cards.json -f list -l /tmp/cbimport_ck.log -g cards::#MONO_INCR#\""
	oc exec -it ${C360_POD} -- bash -c "/opt/couchbase/bin/cbimport json -c couchbase://cb-example-0000 -u ${CB_USER} -p ${CB_PASS} -b ${C360_BUCKET} -d file://tmp/cards.json -f list -l /tmp/cbimport_ck.log -g cards::#MONO_INCR#"

        cp -fp ./resources/templates/cards_fts.json.template ./resources/cards_fts.json

        sed -e "s/###C360_BUCKET###/$C360_BUCKET/g" -i .bkup ./resources/cards_fts.json
	
	log "oc cp ./resources/cards_fts.json ${C360_FTS_POD}:/tmp/cards_fts.json"
	oc cp ./resources/cards_fts.json ${C360_FTS_POD}:/tmp/cards_fts.json

	log "oc exec -it ${C360_FTS_POD} -- bash -c \"curl -u ${CB_USER}:${CB_PASS} -XPUT http://localhost:8094/api/index/cards -H 'content-type: application/json'  -d @/tmp/cards_fts.json\""
	oc exec -it ${C360_FTS_POD} -- bash -c "curl -u ${CB_USER}:${CB_PASS} -XPUT http://localhost:8094/api/index/cards -H 'content-type: application/json'  -d @/tmp/cards_fts.json"
        
	cp -fp ./resources/templates/customers_fts.json.template ./resources/customers_fts.json

        sed -e "s/###C360_BUCKET###/$C360_BUCKET/g" -i .bkup ./resources/customers_fts.json
	
	log "oc cp ./resources/customers_fts.json ${C360_FTS_POD}:/tmp/customers_fts.json"
	oc cp ./resources/customers_fts.json ${C360_FTS_POD}:/tmp/customers_fts.json
	
	log "oc exec -it ${C360_FTS_POD} -- bash -c \"curl -u ${CB_USER}:${CB_PASS} -XPUT http://localhost:8094/api/index/customers -H 'content-type: application/json'  -d @/tmp/customers_fts.json\""
	oc exec -it ${C360_FTS_POD} -- bash -c "curl -u ${CB_USER}:${CB_PASS} -XPUT http://localhost:8094/api/index/customers -H 'content-type: application/json'  -d @/tmp/customers_fts.json"
	
	log "oc exec -it ${C360_POD} -- bash -c \"curl -u ${CB_USER}:${CB_PASS} -XPUT http://localhost:8091/settings/rbac/users/local/$C360_BUCKET -d \"name=$C360_BUCKET&roles=admin,bucket_admin[$C360_BUCKET]&password=${C360_PASSWORD}\""
	oc exec -it ${C360_POD} -- bash -c "curl -u ${CB_USER}:${CB_PASS} -XPUT http://localhost:8091/settings/rbac/users/local/$C360_BUCKET -d \"name=$C360_BUCKET&roles=admin,bucket_admin[$C360_BUCKET]&password=${C360_PASSWORD}\""
	log ""

	log "oc exec -it ${C360_POD} -- bash -c \"curl -u ${CB_USER}:${CB_PASS} -XPOST http://localhost:8093/query/service -d \"statement=create primary index on \`$C360_BUCKET\`\""
	oc exec -it ${C360_POD} -- bash -c "curl -v -u ${CB_USER}:${CB_PASS} -XPOST http://localhost:8093/query/service -d \"statement=create primary index on $C360_BUCKET\""
}

function deploy_app_server
{
	logSection "Deploying Application Server"
	
	verify_status

	MYSQLAPP=`oc get pods | grep $MYSQL_NAME | grep -v deploy | cut -d' ' -f1`
	POSTGRESAPP=`oc get pods | grep $POSTGRESQL_NAME | grep -v deploy | cut -d' ' -f1`

	log "\noc new-app cbck/tomcat-git-mvn-jdk8
	\n\t-e C360_POD=$C360_POD \
	\n\t-e C360_BUCKET=$C360_BUCKET \
	\n\t-e C360_PASSWORD=$C360_PASSWORD \
	\n\t-e C360_MYSQL_HOST=$MYSQLAPP \
	\n\t-e MYSQL_USER=$MYSQL_USER \
	\n\t-e MYSQL_PASSWORD=$MYSQL_PASSWORD \
	\n\t-e C360_POSTGRES_HOST=$POSTGRESAPP \
	\n\t-e POSTGRESQL_DATABASE=$POSTGRESQL_DATABASE \
	\n\t-e POSTGRESQL_USER=$POSTGRESQL_USER \
	\n\t-e POSTGRESQL_PASSWORD=$POSTGRESQL_PASSWORD \
	\n\t-e OPENSHIFT_JENKINS_JVM_ARCH=x86_64 \
	\n"


	
	oc new-app cbck/tomcat-git-mvn-jdk8 \
	-e C360_POD=$C360_POD \
	-e C360_BUCKET=$C360_BUCKET \
	-e C360_PASSWORD=$C360_PASSWORD \
	-e C360_MYSQL_HOST=$MYSQLAPP \
	-e MYSQL_USER=$MYSQL_USER \
	-e MYSQL_PASSWORD=$MYSQL_PASSWORD \
	-e C360_POSTGRES_HOST=$POSTGRESAPP \
	-e POSTGRESQL_DATABASE=$POSTGRESQL_DATABASE \
	-e POSTGRESQL_USER=$POSTGRESQL_USER \
	-e POSTGRESQL_PASSWORD=$POSTGRESQL_PASSWORD \
	--name=app-server

	RETRY_CNT=1
	SUCC_CNT=0
	while [[ $SUCC_CNT -lt 1 && $RETRY_CNT -le $MAX_RETRY ]];do
		log "checking app server status... try $RETRY_CNT"
		SUCC_CNT=`oc get pods | grep "app-server" | grep -v deploy | grep -c "1/1"`
		RETRY_CNT=$((RETRY_CNT+1))
		sleep $RETRY_DELAY
	done

	if [ $SUCC_CNT -lt 1 ];then
		log "App Server did not start..."
		exit 1
	fi

	log "oc expose svc/app-server"
	oc expose svc/app-server
}

function remove_app_server
{
	logSection "Removing app-server"
	verify_status
	
	log "Removing tomcat service"
	count=`oc get svc | grep -c app-server`
	if [ $count -eq 1 ];then
		log "Running: oc delete svc app-server"
		oc delete svc app-server
	fi

	log "Removing tomcat deploymentconfig"
	count=`oc get dc | grep -c app-server`
	if [ $count -eq 1 ];then
		log "Running: oc delete dc app-server"
		oc delete dc app-server
	fi

	log "Removing tomcat buildconfig"
	count=`oc get bc | grep -c app-server`
	if [ $count -eq 1 ];then
		log "Running: oc delete bc app-server"
		oc delete bc app-server
	fi

	log "Removing tomcat imagestream"
	count=`oc get is | grep -c app-server`
	if [ $count -eq 1 ];then
		log "Running: oc delete is app-server"
		oc delete is app-server
	fi

	log "Removing app-server route"
	count=`oc get routes | grep -c app-server`
	if [ $count -eq 1 ];then
		log "Running: oc delete route app-server"
		oc delete route app-server
	fi
}

function deploy_c360_sync
{
	logSection "Deploying C360 Sync Services"

	MYSQLAPP=`oc get -o wide pods | grep $MYSQL_NAME | grep -v deploy | tr -s ' ' | cut -d' ' -f6`
	POSTGRESAPP=`oc get -o wide pods | grep $POSTGRESQL_NAME | grep -v deploy | tr -s ' ' | cut -d' ' -f6`
	C360APP=`oc get -o wide pods | grep $C360_POD | grep -v deploy | tr -s ' ' | cut -d' ' -f6`
	

	log "Cloning git hub"
	APPNAME=`oc get pods | grep app-server | grep -v deploy | cut -d' ' -f1`
	log "oc exec -it $APPNAME -- git clone ${GIT_SYNC_SERVICE_URL} ${GIT_DIR}/couchbase-sync-service"
	oc exec -it $APPNAME -- rm -rf ${GIT_DIR}/couchbase-sync-service
	oc exec -it $APPNAME -- git clone ${GIT_SYNC_SERVICE_URL} ${GIT_DIR}/couchbase-sync-service

	log "Updating application.properties"

	oc exec -it $APPNAME -- bash -c "echo $C360_MYSQL_HOST"

	oc exec -it $APPNAME -- bash -c "sed -e s/###C360_POD###/$C360APP/g -e s/###C360_BUCKET###/$C360_BUCKET/g -e s/###C360_PASS###/$C360_PASSWORD/g \
	-e s/###C360_MYSQL_HOST###/$MYSQLAPP/g \
	-e s/###MYSQL_DATABASE###/$MYSQL_DATABASE/g \
	-e s/###MYSQL_USER###/$MYSQL_USER/g \
	-e s/###MYSQL_PASSWORD###/$MYSQL_PASSWORD/g \
	-e s/###C360_POSTGRES_HOST###/$POSTGRESAPP/g \
	-e s/###POSTGRESQL_DATABASE###/$POSTGRESQL_DATABASE/g \
	-e s/###POSTGRESQL_USER###/$POSTGRESQL_USER/g \
	-e s/###POSTGRESQL_PASSWORD###/$POSTGRESQL_PASSWORD/g \
	/tmp/couchbase-sync-service/src/main/resources/application.properties.template \
	> /tmp/couchbase-sync-service/src/main/resources/application.properties"

	log "oc exec -it $APPNAME -- bash -c \"cd ${GIT_DIR}/couchbase-sync-service && mvn clean install\""
	oc exec -it $APPNAME -- bash -c "cd ${GIT_DIR}/couchbase-sync-service && mvn clean install"

	log "oc exec -it $APPNAME -- bash -c \"cd ${GIT_DIR}/couchbase-sync-service && mvn spring-boot:run\""
	oc exec -it $APPNAME -- bash -c "cd ${GIT_DIR}/couchbase-sync-service && mvn spring-boot:run" 2>&1 > /dev/null &

	log "Sleeping for 40 seconds for spring-boot to load"
	sleep 40
}

function run_c360_sync
{
	logSection "Running the C360 Sync REST Api"

	verify_status
	
	APP=`oc get -o wide pods | grep app-server | grep -v deploy | tr -s ' ' | cut -d' ' -f1`
	log "oc exec -it $APP -- bash -c \"curl -u $C360_BUCKET:$C360_PASSWORD  -XPOST http://localhost:8081/api/sync/customer-data -H 'content-type: application/json'\""
	oc exec -it $APP -- bash -c "curl -u $C360_BUCKET:$C360_PASSWORD  -XPOST http://localhost:8081/api/sync/customer-data -H 'content-type: application/json'"
}

function deploy_c360_ui
{
	logSection "Deploying C360 Sync Services"

	MYSQLAPP=`oc get -o wide pods | grep $MYSQL_NAME | grep -v deploy | tr -s ' ' | cut -d' ' -f6`
	POSTGRESAPP=`oc get -o wide pods | grep $POSTGRESQL_NAME | grep -v deploy | tr -s ' ' | cut -d' ' -f6`
	C360APP=`oc get -o wide pods | grep $C360_POD | grep -v deploy | tr -s ' ' | cut -d' ' -f6`
	

	log "Cloning git hub"
	APPNAME=`oc get pods | grep app-server | grep -v deploy | cut -d' ' -f1`
	log "oc exec -it $APPNAME -- git clone ${GIT_SYNC_UI_URL} ${GIT_DIR}/couchbase-sync-ui"
	oc exec -it $APPNAME -- rm -rf ${GIT_DIR}/couchbase-sync-ui
	oc exec -it $APPNAME -- git clone ${GIT_SYNC_UI_URL} ${GIT_DIR}/couchbase-sync-ui

	log "Updating application.properties"

	oc exec -it $APPNAME -- bash -c "sed -e s/###C360_POD###/$C360APP/g -e s/###C360_BUCKET###/$C360_BUCKET/g -e s/###C360_PASS###/$C360_PASSWORD/g \
	-e s/###C360_MYSQL_HOST###/$MYSQLAPP/g \
	-e s/###MYSQL_DATABASE###/$MYSQL_DATABASE/g \
	-e s/###MYSQL_USER###/$MYSQL_USER/g \
	-e s/###MYSQL_PASSWORD###/$MYSQL_PASSWORD/g \
	-e s/###C360_POSTGRES_HOST###/$POSTGRESAPP/g \
	-e s/###POSTGRESQL_DATABASE###/$POSTGRESQL_DATABASE/g \
	-e s/###POSTGRESQL_USER###/$POSTGRESQL_USER/g \
	-e s/###POSTGRESQL_PASSWORD###/$POSTGRESQL_PASSWORD/g \
	${GIT_DIR}/couchbase-sync-ui/src/main/resources/application.properties.template \
	> ${GIT_DIR}/couchbase-sync-ui/src/main/resources/application.properties"

	log "oc exec -it $APPNAME -- bash -c \"cd ${GIT_DIR}/couchbase-sync-ui && mvn clean install\""
	oc exec -it $APPNAME -- bash -c "cd ${GIT_DIR}/couchbase-sync-ui && mvn clean install"

	log "oc exec -it $APPNAME -- bash -c \"cd ${GIT_DIR}/couchbase-sync-ui && mvn jetty:run\""
	oc exec -it $APPNAME -- bash -c "cd ${GIT_DIR}/couchbase-sync-ui && mvn jetty:run" 2>&1 > /dev/null &

	log "Sleeping for 40 seconds to deploy application"
	sleep 40

}

function deploy_couchmart
{
	logSection "Deploying Couchmart Server"
	
	verify_status

	CBAPP=`oc get -o wide pods | grep $COUCHMART_POD | grep -v deploy | tr -s ' ' | cut -d' ' -f6`

	log "\noc new-app cbck/couchmart
	\n\t-e COUCHMART_NODE=$CBAPP \
	\n\t-e COUCHMART_BUCKET=$COUCHMART_BUCKET \
	\n\t-e COUCHMART_USER=$COUCHMART_USER \
	\n\t-e COUCHMART_PASSWORD=$COUCHMART_PASSWORD \
	\n\t-e COUCHMART_ADMIN_USER=$COUCHMART_ADMIN_USER \
	\n\t-e COUCHMART_ADMIN_PASSWORD=$COUCHMART_ADMIN_PASSWORD \
	\n"


	
	oc new-app cbck/couchmart \
	-e COUCHMART_NODE=$CBAPP \
	-e COUCHMART_BUCKET=$COUCHMART_BUCKET \
	-e COUCHMART_USER=$COUCHMART_USER \
	-e COUCHMART_PASSWORD=$COUCHMART_PASSWORD \
	-e COUCHMART_ADMIN_USER=$COUCHMART_ADMIN_USER \
	-e COUCHMART_ADMIN_PASSWORD=$COUCHMART_ADMIN_PASSWORD \
	--name=couchmart

	RETRY_CNT=1
	SUCC_CNT=0
	while [[ $SUCC_CNT -lt 1 && $RETRY_CNT -le $MAX_RETRY ]];do
		log "checking couchmart status... try $RETRY_CNT"
		SUCC_CNT=`oc get pods | grep "couchmart" | grep -v deploy | grep -c "1/1"`
		RETRY_CNT=$((RETRY_CNT+1))
		sleep $RETRY_DELAY
	done

	if [ $SUCC_CNT -lt 1 ];then
		log "Couchmart did not start..."
		exit 1
	fi

	log "oc expose dc/couchmart --port=8888 --name=couchmart"
	oc expose dc/couchmart --port=8888 --name=couchmart

	log "oc expose svc/couchmart"
	oc expose svc/couchmart
}

function remove_couchmart
{
	logSection "Removing couchmart"
	verify_status
	
		log "Removing couchmart service"
		count=`oc get svc | grep -c couchmart`
		if [ $count -eq 1 ];then
			log "Running: oc delete svc couchmart"
			oc delete svc couchmart
		fi

		log "Removing couchmart deploymentconfig"
		count=`oc get dc | grep -c couchmart`
		if [ $count -eq 1 ];then
			log "Running: oc delete dc couchmart"
			oc delete dc couchmart
		fi

		log "Removing couchmart buildconfig"
		count=`oc get bc | grep -c couchmart`
		if [ $count -eq 1 ];then
			log "Running: oc delete bc couchmart"
			oc delete bc couchmart
		fi

		log "Removing couchmart imagestream"
		count=`oc get is | grep -c couchmart`
		if [ $count -eq 1 ];then
			log "Running: oc delete is couchmart"
			oc delete is couchmart
		fi

		log "Removing couchmart route"
		count=`oc get routes | grep -c couchmart`
		if [ $count -eq 1 ];then
			log "Running: oc delete route couchmart"
			oc delete route couchmart
		fi

}

function usage
{
	 USAGE="Install_Minishift.sh [step 1] [step 2] ... [step N]\n
	 Version :  $VERSION\n
	 \n
	 	\tSteps: \n
	 		\t\tinstall_core		--	Installs Minishift, downloads the CB Operator, Starts minishift and sets up the OC command\n
	 		\t\tstart_minishift		--	Starts Minishift\n
			\t\tlogin			--	Login to OC cluster\n
	 		\t\tcreate_project		--	Creates an OpenShift Project\n
	 		\t\tinstall_crd			--	Installs the Couchbase Custom Resource Definition\n
	 		\t\tget_user			--	Returns the current logged in user\n
	 		\t\tget_status			--	Returns the status of Minishift\n
	 		\t\tcreate_rh_secret		--	Create a RedHat secret for access to RH Docker Images\n
	 		\t\tcreate_operator		--	Create the CB Operator\n
	 		\t\tcreate_cluster_role		--	Creates the cluster role for the service account\n
	 		\t\tcreate_service_account	--	Creates the service account\n
	 		\t\tbind_svc_account		--	Bind the service account to secret\n
	 		\t\tcreate_user_role		--	Create the user role for developer\n
	 		\t\tbind_user			--	Bind the developer account\n
	 		\t\tinstall_cbopctl		--	Install cbopctl tool\n
	 		\t\tcreate_secret		--	Create the CB Super User secret\n
	 		\t\tupsert_cluster		--	Create or Apply a CB Cluster\n
	 		\t\tdelete_cluster		--	Delete the specified cluster\n
	 		\t\tset_env			--	Set minishift oc-env\n
	 		\t\tget_admin_ui		--	Get Admin UI URL\n
	 		\t\tport_forward		--	Port forward from cb-example-0000\n
	\n 
	 	\tComposite Steps: \n
	 		\t\tfull_rollback		--	Perform a full_rollback of all Minishift components (no software uninstalled)\n
	 		\t\tcreate_accounts		--	Creates all accounts and bindings by running the following steps\n
	 							\t\t\t\t\tcreate_rh_secret\n
	 							\t\t\t\t\tcreate_cluster_role\n
	 							\t\t\t\t\tcreate_service_account\n
	 							\t\t\t\t\tbind_svc_account\n
	 							\t\t\t\t\tcreate_user_role\n
	 							\t\t\t\t\tbind_user\n
	 	\n
	 		\t\tfull_deploy			--	Perform a full deployment of OC components by running the following steps\n
	 							\t\t\t\t\tcreate_project\n
	 							\t\t\t\t\tinstall_crd\n
	 							\t\t\t\t\tcreate_accounts\n
	 							\t\t\t\t\tcreate_operator\n
	 							\t\t\t\t\tinstall_cbopctl\n
	 							\t\t\t\t\tcreate_secret\n
	 							\t\t\t\t\tupsert_cluster\n
		\n
	 	\tTwitter Application Steps:\n 
	 		\t\tsetup_s2i		--	Sets up S2I for Java applications, necessary to run new-app build steps\n
	 		\t\tdeploy_twitter_api	--	Deploys the twitter-api java application\n
	 		\t\tremove_twitter_api	--	Remove the twitter-api\n
	 		\t\tdeploy_twitter_ui	--	Deploy the twitter-ui java application\n
	 		\t\tremove_twitter_ui	--	Remove the twitter_ui application\n
	 		\t\tget_twitter_ui		--	Get twitter UI\n
	 		\t\tdeploy_twitter_streamer	--	Deploy the twitter streaming application\n
	 		\t\tremove_twitter_streamer	--	Remove the twitter streaming application\n
	 \n
	       \tCustomer 360 commands: \n
	 		\t\tdeploy_mysql		--	Deploys a MySQL DB\n
	 		\t\tcreate_mysql_user	--	Creates the mysql user\n
			\t\tload_mysql_data	--	Load the data into mysql used by the C360 Demo\n
			\t\tremove_mysql	--	Remove the MySQL Pod\n
	 		\t\tdeploy_postgres	--	Deploys a PostGRE DB\n
			\t\tload_postgres_data	--	Loads the postgresql data used by C360 Demo\n
			\t\tremove_postgres	--	Removes the postgres DB\n
			\t\tsetup_c360_bucket	--	Sets up the Couchbase Bucket for C360 Demo\n
			\t\tdeploy_app_server	--	Deploy an application server to run C360 Demo\n
			\t\tremove_app_server	--	Remove Application Server\n
			\t\tdeploy_c360_sync	--	Deploys the C360 Demo Sync Services\n
			\t\trun_c360_sync	--	Run the C360 Sync REST Api\n
			\t\tdeploy_c360_ui	--	Deploy the C360 UI \n
	\n
		\tCouchmart commands: \n
			\t\tdeploy_couchmart	--	Deploys the couchmart application \n
			\t\tremove_couchmart	--	Remove couchmart \n
	"
	echo $USAGE | more
}


#=====================================================================#
#	Main Program
#=====================================================================#

clear

if [ "$#" -eq 0 ];then
	usage
fi

for var in "$@"
do
	case "$var" in
		-h|--help)
			usage
			break
			;;
		install_core)
			install_core
			;;
		start_minishift)
			start_minishift
			;;
		install_crd)
			checkOC
			install_crd
			;;
		get_user)
			checkOC
			get_user
			;;
		get_status)
			get_status
			;;
		create_rh_secret)
			checkOC
			create_rh_secret
			;;
		create_operator)
			checkOC
			create_operator
			;;
		create_cluster_role)
			checkOC
			create_cluster_role
			;;
		create_service_account)
			checkOC
			create_service_account
			;;
		bind_svc_account)
			checkOC
			bind_svc_account
			;;
		create_user_role)
			checkOC
			create_user_role
			;;
		bind_user)
			checkOC
			bind_user
			;;
		install_cbopctl)
			install_cbopctl
			;;
		create_secret)
			checkOC
			create_secret
			;;
		create_project)
			checkOC
			create_project
			;;
		create_accounts)
			checkOC
			create_accounts
			;;
		full_rollback)
			checkOC
			full_rollback
			;;
		set_env)
			set_env
			;;
		full_deploy)
			checkOC
			full_deploy
			;;
		checkOC)
			checkOC
			;;
		upsert_cluster)
			upsert_cluster
			;;
		delete_cluster)
			delete_cluster
			;;
		get_admin_ui)
			checkOC
			get_admin_ui
			;;
		setup_s2i)
			checkOC
			setup_s2i
			;;
		deploy_twitter_api)
			checkOC
			deploy_twitter_api
			;;
		remove_twitter_api)
			checkOC
			remove_twitter_api
			;;
		deploy_twitter_ui)
			checkOC
			deploy_twitter_ui
			;;
		remove_twitter_ui)
			checkOC
			remove_twitter_ui
			;;
		get_twitter_ui)
			checkOC
			get_twitter_ui
			;;
		deploy_twitter_streamer)
			checkOC
			deploy_twitter_streamer
			;;
		remove_twitter_streamer)
			checkOC
			remove_twitter_streamer
			;;
		deploy_mysql)
			checkOC
			deploy_mysql
			;;
		deploy_postgres)
			checkOC
			deploy_postgres
			;;
		port_forward)
			checkOC
			port_forward
			;;
		create_mysql_user)
			checkOC
			create_mysql_user
			;;
		load_mysql_data)
			checkOC
			load_mysql_data
			;;
		remove_mysql)
			checkOC
			remove_mysql
			;;
		load_postgres_data)
			checkOC
			load_postgres_data
			;;
		remove_postgres)
			checkOC
			remove_postgres
			;;
		setup_c360_bucket)
			checkOC
			setup_c360_bucket
			;;
		deploy_app_server)
			checkOC
			deploy_app_server
			;;
		remove_app_server)
			checkOC
			remove_app_server
			;;
		deploy_c360_sync)
			checkOC
			deploy_c360_sync
			;;
		login)
			checkOC
			login
			;;
		run_c360_sync)
			checkOC
			run_c360_sync
			;;
		deploy_c360_ui)
			checkOC
			deploy_c360_ui
			;;
		deploy_couchmart)
			checkOC
			deploy_couchmart
			;;
		remove_couchmart)
			checkOC
			remove_couchmart
			;;
		*)
			log "Unknown command $var, ignoring..."
			;;
	esac
done

#Put some space before returning console to user
echo ""
echo ""

#Turn off trap
trap - ERR
