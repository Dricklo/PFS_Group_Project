library(coXpress)
library(WGCNA)          ###used for topological overlap calculation and clustering steps
library(RColorBrewer)   ###used to create nicer colour palettes
library(preprocessCore) ###used by the quantile normalization function
library(flashClust)
library(ggplot2)
library(tidyverse)
theme_set(theme_classic())

# R code for data pipeline. input is the processed data from Go 
# output is the resulting identified clusters

golub.df <- read.table("golub.txt", sep="\t", header=TRUE, row.names=1)

# DiffCoEx----------------------------------------------------------------------
datC1 <- t(golub.df[,1:27]) # ALL condition
datC2 <- t(golub.df[,28:38]) # AML condition

beta1=6 #user defined parameter for soft thresholding
AdjMatC1<-sign(cor(datC1,method="spearman"))*(cor(datC1,method="spearman"))^2
AdjMatC2<-sign(cor(datC2,method="spearman"))*(cor(datC2,method="spearman"))^2
diag(AdjMatC1)<-0
diag(AdjMatC2)<-0
collectGarbage()

dissTOMC1C2=TOMdist((abs(AdjMatC1-AdjMatC2)/2)^(beta1/2))
collectGarbage()

#Hierarchical clustering is performed using the Topological Overlap of the adjacency difference as input distance matrix
# make sure to install this 
geneTreeC1C2 = flashClust(as.dist(dissTOMC1C2), method = "average"); 

#We now extract modules from the hierarchical tree. This is done using cutreeDynamic. Please refer to WGCNA package documentation for details
dynamicModsHybridC1C2 = cutreeDynamic(dendro = geneTreeC1C2, distM = dissTOMC1C2,method="hybrid",cutHeight=.996,deepSplit = T, pamRespectsDendro = FALSE,minClusterSize = 20);

#Every module is assigned a color. Note that GREY is reserved for genes which do not belong to any differentially coexpressed module
dynamicColorsHybridC1C2 = labels2colors(dynamicModsHybridC1C2)

#the next step merges clusters which are close (see WGCNA package documentation)
mergedColorC1C2<-mergeCloseModules(rbind(datC1,datC2),dynamicColorsHybridC1C2,cutHeight=.2)$color
colorh1C1C2<-mergedColorC1C2

# use rownames from golub.df because we are vertically stack datc1 and datc2
diffcoex_results <- data.frame(Gene = rownames(golub.df), Cluster = colorh1C1C2)

# export diffcoex results
write.csv(coxpress_results, filepath1, row.names=FALSE)

# CoXpress----------------------------------------------------------------------
# ALL cases are in columns 1-27
hc.gene  <- cluster.gene(golub.df[,1:27],s="pearson",m="average")
g <- cutree(hc.gene, h=0.4)

# make the formatting a bit nicer
coxpress_results <- data.frame(g) |>
  rownames_to_column("gene") # these are the gene markers

# rename columns 
colnames(coxpress_results) <- c("Gene", "Cluster")

# export coxpress results
write.csv(coxpress_results, filepath1, row.names=FALSE)

# Clustering analysis-----------------------------------------------------------
# check to see if genes are the same in both results 
if (setequal(diffcoex_results$Gene, coxpress_results$Gene)) {
  print("Both methods have the same genes.")
} else {
  print("The methods have different genes.")
}

# Calculate Genes Per Cluster as a numeric vector
genes_per_cluster_diffcoex <- as.numeric(table(diffcoex_results$Cluster))
genes_per_cluster_coxpress <- as.numeric(table(coxpress_results$Cluster))

# Compute summary statistics
diffcoex_summary <- list(
  Total_Genes = nrow(diffcoex_results),
  Total_Clusters = length(unique(diffcoex_results$Cluster)),
  Genes_Per_Cluster = summary(genes_per_cluster_diffcoex)  # Correct summary
)

coxpress_summary <- list(
  Total_Genes = nrow(coxpress_results),
  Total_Clusters = length(unique(coxpress_results$Cluster)),
  Genes_Per_Cluster = summary(genes_per_cluster_coxpress)  # Correct summary
)

# Print the summaries
cat("DiffCoEx Summary:\n")
print(diffcoex_summary)
cat("\nCoXpress Summary:\n")
print(coxpress_summary)

# Check number of clusters for each method 
num_clusters_diffcoex <- length(unique(diffcoex_results$Cluster))
num_clusters_coxpress <- length(unique(coxpress_results$Cluster))
num_clusters <- data.frame(Method = c("DiffCoEx", "CoXpress"),
                           Clusters = c(num_clusters_diffcoex, num_clusters_coxpress))
ggplot(num_clusters, aes(x = Method, y = Clusters, fill = Method)) +
  geom_bar(stat = "identity", show.legend = FALSE) +
  labs(title = "Number of Clusters by Method", x = "Method", y = "Number of Clusters") +
  theme_minimal() +
  theme(text = element_text(size = 14))

# Count the number of genes in each cluster
genes_per_cluster_diffcoex <- table(diffcoex_results$Cluster)

# Convert to a data frame for ggplot
genes_per_cluster_df_diffcoex <- as.data.frame(genes_per_cluster_diffcoex)
colnames(genes_per_cluster_df_diffcoex) <- c("Cluster", "Gene Count")

# Create the bar chart
ggplot(genes_per_cluster_df_diffcoex, aes(x = Cluster, y = `Gene Count`)) +
  geom_bar(stat = "identity", fill = "blue", alpha = 0.7) +
  labs(title = "Number of Genes Per Cluster - DiffCoEx", x = "Cluster", y = "Number of Genes") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 90, hjust = 1),
        text = element_text(size = 14))

# Count the number of genes in each cluster
genes_per_cluster_coxpress <- table(coxpress_results$Cluster)

# Convert to a data frame for ggplot
genes_per_cluster_df_coxpress <- as.data.frame(genes_per_cluster_coxpress)
colnames(genes_per_cluster_df_coxpress) <- c("Cluster", "Gene Count")

# Create the bar chart
ggplot(genes_per_cluster_df_coxpress, aes(x = Cluster, y = `Gene Count`)) +
  geom_bar(stat = "identity", fill = "orange", alpha = 0.7) +
  labs(title = "Number of Genes Per Cluster - CoXpress", x = "Cluster", y = "Number of Genes") +
  theme_minimal() +
  theme(axis.text.x = element_blank(),    
        axis.ticks.x = element_blank(),  
        text = element_text(size = 14))

# heatmap to show similarity between clusters created from both methods 
# Merge data to compare modules
merged_data <- merge(diffcoex_results, coxpress_results, by = "Gene", suffixes = c("_DiffCoEx", "_CoXpress"))

# Create a table of shared genes between modules
shared_genes_table <- table(merged_data$Cluster_DiffCoEx, merged_data$Cluster_CoXpress)

# Convert to a data frame for visualization
shared_genes_df <- as.data.frame(as.table(shared_genes_table))
colnames(shared_genes_df) <- c("DiffCoEx_Module", "CoXpress_Module", "Gene_Count")

# Filter CoXpress modules with significant overlap (at least 5 shared genes)
filtered_shared_genes_df <- shared_genes_df[shared_genes_df$Gene_Count >= 5, ]

# Create the heatmap
ggplot(filtered_shared_genes_df, aes(x = CoXpress_Module, y = DiffCoEx_Module, fill = Gene_Count)) +
  geom_tile(color = "white") +
  scale_fill_gradient(low = "white", high = "blue", name = "Gene Overlap") +
  labs(title = "Gene Overlap Between DiffCoEx and CoXpress Modules",
       x = "CoXpress Modules",
       y = "DiffCoEx Modules") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 90, hjust = 1),
        text = element_text(size = 12))

