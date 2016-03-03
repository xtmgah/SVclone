# get a metric for stability of clusters

args <- commandArgs(trailingOnly = TRUE)

if(length(args)==0 | args[1]=='-h') {
    print('Usage: Rscript <workingdir> <sample id> --map')
}

setwd(args[1])
id <- args[2]
map <- args[3]

require(combinat)
require(RColorBrewer)
require(gplots)
require(ggplot2)
require(gridExtra)
require(reshape)

# Get number of runs
runs <- c()
for (dir in list.dirs()) {
    cur_dir <- strsplit(dir,'/')[[1]]
    if (length(cur_dir) <= 1)
        next
    cur_dir <- cur_dir[2]
    if (substring(cur_dir,1,3) == 'run') {
        runs <- c(runs,cur_dir)
    }
}
    
############################################################################################
# Cluster stability of runs
############################################################################################

compare_runs <- function(run1, run2) {
    clus_cert_file <- paste(run1, '/', id, '_cluster_certainty.txt', sep='')
    clus_cert1 <- read.delim(clus_cert_file, sep='\t', stringsAsFactors=F)
    
    clus_cert_file <- paste(run2, '/', id, '_cluster_certainty.txt', sep='')
    clus_cert2 <- read.delim(clus_cert_file, sep='\t', stringsAsFactors=F)
    
    clus1 <- as.numeric(names(table(clus_cert1$most_likely_assignment)))
    dist <- 0
    for (clus in clus1) {
        if (sum(clus_cert1$most_likely_assignment == clus) <= 1)
            next
        
        cert1_tmp <- clus_cert1[clus_cert1$most_likely_assignment == clus,]
        cert2_tmp <- clus_cert2[clus_cert1$most_likely_assignment == clus,]
        
        points_in_clus <- nrow(cert1_tmp)
        combs <- t(combn(points_in_clus, 2))
        for (i in 1:nrow(combs)) {
            pair <- combs[i,]
            clus_in_2 <- cert2_tmp[pair, 'most_likely_assignment']
            if (clus_in_2[1] != clus_in_2[2]) {
                dist <- dist + 1
            }
        }
    }
    
    total_combs <- ncol(combn(nrow(clus_cert1), 2))
    #print(paste('Dist:', dist, ';', 'combs:', total_combs))
    metric <- 1 - (dist / total_combs)
    #print('-------------------')
    return(metric)
}

all_comps <- combn(runs,2)
n <- length(runs)

results <- matrix(0, n, n)
colnames(results) <- runs
rownames(results) <- runs

for (i in 1:nrow(results)) {
    for (j in 1:ncol(results)) {
        run1 <- rownames(results)[i]
        run2 <- colnames(results)[j]
        if (run1 == run2) {
            results[i, j] <- 1.
        } else {
            results[i, j] <- compare_runs(run1, run2)
        }
    }
}

# cluster stability metric plot
pdf(paste(id, '_cluster_stability_heatmap.pdf',sep=''),height=6)
cols <- colorRampPalette(brewer.pal(9,'Blues'))(30)
heatmap.2(results, trace='none', Rowv=F, Colv=F, dendrogram='none', col=cols)
dev.off()

results <- cbind(rownames(results), results)
write.table(results, paste(id,'_cluster_stability.csv', sep=''), sep=',', quote=F, row.names=F)

# cluster proportions plot
clusts <- NULL
for (run in runs) {
    sv_clust <- read.table(paste(run, '/', id, '_subclonal_structure.txt', sep=''), 
                           header=T, sep='\t', stringsAsFactors=F)
    clusts <- rbind(clusts, data.frame(run=run, n_ssms=sv_clust$n_ssms, cluster=sv_clust$cluster))
}

pdf(paste(id, '_cluster_hist.pdf',sep=''),height=4, width=max(3,length(runs)*0.6))
ggplot(clusts, aes(x=factor(run), y=n_ssms, fill=factor(cluster))) + geom_bar(stat='identity')
dev.off()

############################################################################################
# Plot AIC and BIC for runs
############################################################################################

if (length(args)==3 & map == '--map') {
    ic_table <- NULL
    for (run in runs) {
        ic <- read.table(paste(run, '/', id, '_fit.txt', sep=''), sep='\t', header=F)
        ic <- cbind(run=run, ic)
        ic_table <- rbind(ic_table, ic)
    }
    
    pdf(paste(id, 'aic_bic_plot.pdf',sep='_'), height=4)
    print(ggplot(ic_table, aes(y=V2, x=run, group=V1, color=factor(V1))) + ylab('value') + geom_line())
    dev.off()
    
    ic_table <- cast(ic_table, run~V1, value='V2')
    min_bic <- ic_table[min(ic_table$BIC)==ic_table$BIC,]
    min_bic$AIC <- min_bic$run
    min_bic$run <- 'min_BIC'
    ic_table <- rbind(ic_table, min_bic)
    
    min_aic <- ic_table[min(ic_table$AIC)==ic_table$AIC,]
    min_aic$BIC <- min_aic$run
    min_aic$run <- 'min_AIC'
    ic_table <- rbind(ic_table, min_aic)
    
    write.table(ic_table, paste(id,'_aic_bic_metrics.csv', sep=''), sep=',', quote=F, row.names=F)
}

############################################################################################
# Plot histogram of clusters + QQ plots
############################################################################################

get_adjust_factor <- function(svs, pur) {
    cn <- svs$most_likely_variant_copynumber
    mut_prop <- svs$prop_chrs_bearing_mutation
    vaf <- svs$adjusted_vaf
    prob <- (cn * mut_prop * pur) / (2 * (1 - pur) + cn * pur)
    return((1 / prob))
}

svs <- read.table(paste(id, '_filtered_svs.tsv', sep=''), header=T, sep='\t', stringsAsFactors=F)
pur <- read.table('purity_ploidy.txt',header=T, sep='\t', stringsAsFactors=F)$purity

gg_color_hue <- function(n) {
    hues = seq(15, 375, length=n+1)
    hcl(h=hues, l=65, c=100)[1:n]
}

ggQQ <- function(dat) {
    p <- ggplot(dat) +
        stat_qq(aes(sample=CCF, colour = factor(most_likely_assignment)), alpha = 0.5)
    
    dat <- dat[!is.na(dat$CCF),]
    
    clusts <- as.numeric(names(table(dat$most_likely_assignment)))
    cols <- gg_color_hue(length(clusts))
    
    for (i in 1:length(clusts)) {
        clus <- clusts[i]
        tmp <- dat[dat$most_likely_assignment == clus, 'CCF'] 
        y <- quantile(tmp, c(0.25, 0.75))
        x <- qnorm(c(0.25, 0.75))
        slope <- diff(y)/diff(x)
        intercept <- y[1L] - slope * x[1L]   
        
        p <- p + geom_abline(slope = slope, intercept = intercept, color=cols[i], alpha=0.5)
    }
    
    return(p)
}

for (run in runs) {        
    mlcn <- read.table(paste(run, '/', id, '_most_likely_copynumbers.txt', sep=''), header=T, sep='\t', stringsAsFactors=F)    
    dat <- merge(svs, mlcn, by.x=c(2,3,5,6), by.y=c(1,2,3,4))
    certain <- read.table(paste(run, '/', id, '_cluster_certainty.txt', sep=''), sep='\t', header=T)
    dat <- merge(dat, certain,by.x=c(1,2,3,4), by.y=c(1,2,3,4))
    dat <- cbind(dat, CCF=get_adjust_factor(dat, pur) * dat$adjusted_vaf)
    
    sv_clust <- read.table(paste(run, '/', id, '_subclonal_structure.txt', sep=''), header=T, sep='\t', stringsAsFactors=F)
    sv_clust <- sv_clust[sv_clust$n_ssms>1, ]
    dat <- dat[dat$most_likely_assignment%in%sv_clust$cluster,]    
    
    above_ssm_th <- sv_clust$n_ssms / (sum(sv_clust$n_ssms)) > 0.1
    below_ssm_th <- sv_clust$n_ssms / (sum(sv_clust$n_ssms)) < 0.1
    clus_intercepts <- 1 / pur * as.numeric(sv_clust$proportion[above_ssm_th & sv_clust$n_ssms > 2])
    clus_intercepts_minor <- 1 / pur * as.numeric(sv_clust$proportion[below_ssm_th | sv_clust$n_ssms<=2])
        
    plot1 <- ggplot(dat, aes(x=as.numeric(dat$CCF), 
                    fill=factor(most_likely_assignment), color=factor(most_likely_assignment))) + 
                    xlim(0,2) + geom_histogram(alpha=0.3,position='identity',binwidth=0.05)+xlab('CCF') +
                    geom_vline(xintercept=clus_intercepts, colour='blue', size=1)+
                    geom_vline(xintercept=clus_intercepts_minor,colour='red',lty=2)
        
    plot2 <- ggQQ(dat)
    
    pdf(paste(id, run, 'fit.pdf',sep='_'),height=7)
    grid.arrange(plot1, plot2)
    dev.off()
}
