# Credit Portfolio Risk Analysis

The pipeline: Dataset from kaggle.com
Loan_Default.csv → MySQL (clean) → Excel → Power BI

### Smaller loans default more often —
loans under $150K default at 31.8%, vs. 20.3% for the $450–600K band. This likely reflects 
who takes out small loans (thinner-margin borrowers) rather than loan size itself causing risk

Credit score shows no meaningful relationship with default risk in this dataset — unlike typical lending data, where it's usually the strongest predictor.
 
### LTV is the strongest, most intuitive predictor — but not in a straight line:

LTV band	Default rate
≤60% (low leverage)	    13.9%
60–80%	                33.2% (highest)
80–95%	                18.4%
>95% (highest leverage)	26.8%

### Region is a real risk signal — North-East is the outlier.

Region	Default rate
North	22.5%
South	26.6%
Central	27.5%
North-East	30.4%
