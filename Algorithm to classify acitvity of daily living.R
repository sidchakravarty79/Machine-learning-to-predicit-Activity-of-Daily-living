library("ggplot2")
library("gridExtra")
library("dplyr")
library("e1071")
library("FBN")
library("caret")
library("fpc")
library("mvoutlier")
library("som")
library("doparallel")
library("DMwR")
library("dtt")
library("ROCR")
library("pROC")
library("plotly")
################################################

# Lists file in the root main and subfolders
hmpfiles <- list.files(recursive = T,ignore.case = T,pattern = "H*.txt")

if (file.exists("data3.csv") == T) {file.remove("data2.csv")}

### Functions for  noise  filtering and data scaling
noise_fil<- function (i) {
  (-14.709) + (((i)/63) * (2*14.709))
}

median_fil<- function (i) {
medianFilter(i,windowSize = 3)
}
scaling <-function(x) {
  (x - min(x))/diff(range(x))
}

Sum_act<-data.frame()

##### Reads the files
for (i in 1:828) {
names<-noquote(unlist(strsplit(hmpfiles[i],"[/,.-]")))
file<-read.table(hmpfiles[i])
rows<-nrow(read.table(hmpfiles[i]))
lapply(file, noise_fil)
lapply(file, median_fil)
sv<-svd(scale(file[,-4]))
file<-mutate(file,sv =sqrt( V1^2+V2^2+V3^2))   ## Sum of vector magnitude formulae (SVM)
file$dt<-dtt(file$sv,type = "dct",variant = 2) ## Discrete cosine transformation
Sum_act<-summarise(file,sum(dt)/rows)
Sum_act$svd1<-sv$d[1]                          ## Singular value decomposition
Sum_act$svd2<-sv$d[2] 
Sum_act$act<-names[9]
write.table(Sum_act,"data3.csv",append = T,sep=",",row.names = F,col.names = F) 
 } ### Output the mutated file.

#### Read mutated file 
dcs_comb<-read.csv("data3.csv",header = T,col.names = c("VM","SVD1","SVD2","Act"))

ggplot (aes(x = SVD1,fill=Act),data = dcs_comb) + geom_histogram(binwidth = 1,na.rm = T) + 
  facet_grid(Act~.,scale="free") + theme_bw(base_size = 12, base_family = "") +
  theme(panel.grid.major = element_line(colour = "white")) + theme(panel.border = element_rect(linetype = "solid", 
                                                                                               colour = "white"))
ggplot(aes(x = SVD2,fill=Act),data = dcs_comb) + geom_histogram(binwidth = 1,na.rm = T) + 
  facet_grid(Act~.,scale="free") + theme_bw(base_size = 12, base_family = "") +
  theme(panel.grid.major = element_line(colour = "white")) + theme(panel.border = element_rect(linetype = "solid", 
                                                                                               colour = "white"))
ggplot(aes(x = VM,fill=Act),data = dcs_comb) + geom_histogram(binwidth=1,na.rm = T) + 
  facet_grid(Act~.,scale="free") + theme_bw(base_size = 12, base_family = "") +
  theme(panel.grid.major = element_line(colour = "white")) + theme(panel.border = element_rect(linetype = "solid", 
                                                                                               colour = "white"))
ggplot(aes(x = Act,fill=Act),data = dcs_comb) + geom_boxplot(na.rm = T) + 
  theme_bw(base_size = 12, base_family = "") +
  theme(panel.grid.major = element_line(colour = "white"))

#Scale all values between 0 and 1
activities<-dcs_comb %>% select(Act)
fun_sum <- as.data.frame(lapply(dcs_comb[,-4],scaling))
files_dcs<-cbind(fun_sum,activities)

#Generate synthetic data points to account for unbalanced data
files_smote_vd<-SMOTE(Act~.,files_dcs[,-1],perc.over= 1000,perc.under = 1500,k=5)
files_smote_svd<-SMOTE(Act~.,files_dcs,perc.over= 1000,perc.under = 1500,k=5)

ggplot (aes(x = SVD1,fill=Act),data = files_dcs) + geom_histogram(binwidth = 0.05,na.rm = T) + 
  facet_grid(Act~.,scale="free") + theme_bw(base_size = 12, base_family = "") +
  theme(panel.grid.major = element_line(colour = "white")) + theme(panel.border = element_rect(linetype = "solid", 
                                                                                               colour = "white"))
ggplot(aes(x = SVD2,fill=Act),data = files_dcs) + geom_histogram(binwidth = 0.05,na.rm = T) + 
  facet_grid(Act~.,scale="free") + theme_bw(base_size = 12, base_family = "") +
  theme(panel.grid.major = element_line(colour = "white")) + theme(panel.border = element_rect(linetype = "solid", 
                                                                                               colour = "white"))
ggplot(aes(x = VM,fill=Act),data = files_dcs) + geom_histogram(binwidth=0.05,na.rm = T) + 
  facet_grid(Act~.,scale="free") + theme_bw(base_size = 12, base_family = "") +
  theme(panel.grid.major = element_line(colour = "white")) + theme(panel.border = element_rect(linetype = "solid", 
                                                                                               colour = "white"))

##### Partition the data into Test and Train for SVM (vector mangnitude)
split_vd<-createDataPartition(y=files_smote_vd$Act,p=0.7, list = FALSE)
traindata_vd<-as.data.frame(files_smote_vd[split,])
testdata_vd<-files_smote_vd[-split,]

##### Partition the data into Test and Train for SVD (singular value decomposition)
split_svd<-createDataPartition(y=files_smote_svd$Act,p=0.7, list = FALSE)
traindata_svd<-as.data.frame(files_smote_svd[split,])
testdata_svd<-files_smote_svd[-split,]

#Tune support vector model and optimize the cost and gamma parameters through corss validation (10X)
tune_model_vd<-tune.svm(Act~.,data = traindata_vd,kernel="radial",cost= seq(800,900,by=10),
                        gamma =seq(18,20,by=0.5), tunecontrol= tune.control(sampling ="cross",cross = 10))

#Train SVM model for using train data for optimized cost and gamma parameters
train_svm<-svm(Act~.,data = traindata_vd,type= "C", kernel="radial", cost=900,
               gamma = 20,probability=TRUE)

#Run  the model againt training data
train_p<-predict(train_svm,traindata_vd,probability=TRUE)
act_label<-(levels(traindata_vd$Act))
cm<-confusionMatrix(train_p,traindata_vd[,3])
plot(train_svm,traindata_vd)

#Clear plot
col_lines <- seq(25:36)
lt<-seq(11:30)
plot.new()
axis(1)
axis(2)
box()
abline(0,1,col="darkblue",lwd=3,lty="dashed")
area_train<-data.frame(nrow=11,ncol=2)

#Plot ROC curves for TRAIN data
for (i in 1:11) {
  prob.act<-attr(train_p,"prob")[,act_label[i]]
  label<- ifelse(traindata_vd$Act == act_label[i],1,0)
  roc<-prediction(prob.act,label)
  perf<-performance(roc,"tpr","fpr")
  a<-performance(pred,"auc")
  area_train[i,1]<-(a@y.values)
  area_train[i,2]<-act_label[i]
  plot(perf,add=T,colorize=F,col=col_lines[i],lwd=2,lty=lt[i])
}
legend(x = 0.56,y = 0.6,cex=0.8,text.font=0.5,lwd=2,lty=lt,bty="n",col=col_lines,legend =act_label)

#Test model for TEST data
test_p<-predict(train_svm,testdata_vd,probability=TRUE)
act_label<-(levels(testdata_vd$Act))
cm<-confusionMatrix(test_p,testdata_vd[,3])

#Clear plot
col_lines <- seq(25:36)
lt<-seq(11:30)
plot.new()
axis(1)
axis(2)
box()
abline(0,1,col="darkblue",lwd=3,lty="dashed")
area_test<-data.frame(nrow=11,ncol=2)

#Plot ROC curves for test
for (i in 1:11) {
  prob.act<-(attr(test_p,"probabilities")[,act_label[i]])
  label<- ifelse(testdata_vd$Act == act_label[i],1,0)
  roc<-prediction(prob.act,label)
  perf<-performance(roc,"tpr","fpr")
  a<-performance(pred,"auc")
  area_test[i,1]<-(a@y.values)
  area_test[i,2]<-act_label[i]
  plot(perf,add=T,colorize=F,col=col_lines[i],lwd=2,lty=lt[i],xlab="fpr",ylab="tpr")
}
legend(x = 0.56,y = 0.6,cex=0.8,text.font=0.5,lwd=2,lty=lt,bty="n",col=col_lines,legend =act_label)

#####################################
#Train VD model with train data
train_svm_svd<-svm(Act~.,data = traindata_svd,type= "C", kernel="radial", cost=800,
                   gamma = 18,probability=TRUE)
train_p_svd<-predict(train_svm_svd,traindata_svd,probability=TRUE)
act_label<-(levels(traindata_svd$Act))
cm<-confusionMatrix(train_p_svd,traindata_svd[,4])

#Clear plot
col_lines <- seq(25:36)
lt<-seq(11:30)
plot.new()
axis(1)
axis(2)
box()
abline(0,1,col="darkblue",lwd=3,lty="dashed")
area_train<-data.frame(nrow=11,ncol=2)

#Plot ROC curves for train
for (i in 1:11) {
  prob.act<-(attr(train_p_svd,"probabilities")[,act_label[i]])
  label<- ifelse(traindata_svd$Act == act_label[i],1,0)
  roc<-prediction(prob.act,label)
  perf<-performance(roc,"tpr","fpr")
  a<-performance(pred,"auc")
  area_train[i,1]<-(a@y.values)
  area_train[i,2]<-act_label[i]
  plot(perf,add=T,colorize=F,col=col_lines[i],lwd=2,lty=lt[i])
}
legend(x = 0.56,y = 0.6,cex=0.8,text.font=0.5,lwd=2,lty=lt,bty="n",col=col_lines,legend =act_label)

#Test VD model using test data

test_p_svd<-predict(train_svm_svd,testdata_svd,probability=TRUE)
cm<-confusionMatrix(test_p_svd,testdata_svd[,4])
#Clear plot
col_lines <- seq(25:36)
lt<-seq(11:30)
plot.new()
axis(1)
axis(2)
box()
abline(0,1,col="darkblue",lwd=3,lty="dashed")
area_train<-data.frame(nrow=11,ncol=2)

#Plot ROC curves for train
for (i in 1:11) {
  prob.act<-(attr(test_p_svd,"probabilities")[,act_label[i]])
  label<- ifelse(testdata_svd$Act == act_label[i],1,0)
  roc<-prediction(prob.act,label)
  perf<-performance(roc,"tpr","fpr")
  a<-performance(pred,"auc","acc")
  b<-performance(pred,"f")
  area_test[i,1]<-(a@y.values)
  area_test[i,2]<-act_label[i]
  plot(perf,add=T,colorize=F,col=col_lines[i],lwd=2,lty=lt[i])
}
legend(x = 0.56,y = 0.6,cex=0.8,text.font=0.5,lwd=2,lty=lt,bty="n",col=col_lines,legend =act_label)

### End